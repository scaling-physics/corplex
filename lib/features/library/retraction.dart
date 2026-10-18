import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'metadata_lookup.dart';
import 'openalex.dart' show normalizeCitationDoi;

/// What a notice says about the paper it updates.
enum NoticeKind { retraction, withdrawal, expressionOfConcern, correction }

extension NoticeKindText on NoticeKind {
  /// Retractions and withdrawals are the serious ones: they get the error
  /// tone and the Library marker.
  bool get isSerious =>
      this == NoticeKind.retraction || this == NoticeKind.withdrawal;

  String get noun => switch (this) {
    NoticeKind.retraction => 'Retracted',
    NoticeKind.withdrawal => 'Withdrawn',
    NoticeKind.expressionOfConcern => 'Expression of concern issued',
    NoticeKind.correction => 'Corrected',
  };
}

NoticeKind? _kindOf(String? type) => switch (type?.toLowerCase()) {
  'retraction' => NoticeKind.retraction,
  'withdrawal' => NoticeKind.withdrawal,
  'expression_of_concern' => NoticeKind.expressionOfConcern,
  'correction' || 'erratum' || 'corrigendum' => NoticeKind.correction,
  _ => null,
};

/// One notice (a retraction note, a correction…) that updates a paper.
class UpdateNotice {
  const UpdateNotice({required this.kind, required this.noticeDoi, this.date});

  final NoticeKind kind;

  /// The DOI of the notice itself.
  final String noticeDoi;
  final DateTime? date;

  Uri get link => Uri.https('doi.org', '/$noticeDoi');

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'noticeDoi': noticeDoi,
    'date': date?.toUtc().toIso8601String(),
  };

  factory UpdateNotice.fromJson(Map<String, dynamic> j) => UpdateNotice(
    kind: NoticeKind.values.byName(j['kind'] as String),
    noticeDoi: j['noticeDoi'] as String,
    date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
  );

  /// "Retracted on 12 March 2024 — see the notice".
  String get message {
    final d = date;
    final on = d == null
        ? ''
        : ' on ${d.day} ${_months[d.month - 1]} ${d.year}';
    return '${kind.noun}$on — see the notice';
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime? _dateOf(Object? updated, Object? issued) {
  for (final source in [updated, issued]) {
    if (source is! Map) continue;
    final ts = source['timestamp'];
    final parts = source['date-parts'];
    if (parts is List && parts.isNotEmpty && parts.first is List) {
      final l = (parts.first as List).whereType<num>().toList();
      if (l.isNotEmpty) {
        return DateTime.utc(
          l[0].toInt(),
          l.length > 1 ? l[1].toInt() : 1,
          l.length > 2 ? l[2].toInt() : 1,
        );
      }
    }
    if (ts is num) {
      return DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true);
    }
  }
  return null;
}

/// Reads Crossref's `works?filter=updates:<doi>` answer: the notices whose
/// `update-to` names [doi], serious ones first, then by date.
List<UpdateNotice> parseUpdateNotices(Map<String, dynamic> json, String doi) {
  final items = (json['message'] as Map?)?['items'];
  if (items is! List) return const [];
  final target = doi.toLowerCase();
  final out = <UpdateNotice>[];
  final seen = <String>{};
  for (final item in items) {
    if (item is! Map) continue;
    final noticeDoi = item['DOI'] as String?;
    if (noticeDoi == null) continue;
    final updates = item['update-to'];
    if (updates is! List) continue;
    for (final u in updates) {
      if (u is! Map || '${u['DOI']}'.toLowerCase() != target) continue;
      final kind = _kindOf(u['type'] as String?);
      if (kind == null || !seen.add('${kind.name}|$noticeDoi')) continue;
      out.add(
        UpdateNotice(
          kind: kind,
          noticeDoi: noticeDoi,
          date: _dateOf(u['updated'], item['issued']),
        ),
      );
    }
  }
  out.sort((a, b) {
    if (a.kind.isSerious != b.kind.isSerious) return a.kind.isSerious ? -1 : 1;
    return (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0));
  });
  return out;
}

/// Notices as last fetched.
class RetractionRecord {
  const RetractionRecord({
    required this.doi,
    required this.fetchedAt,
    required this.notices,
  });

  final String doi;
  final DateTime fetchedAt;
  final List<UpdateNotice> notices;

  Map<String, dynamic> toJson() => {
    'doi': doi,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'notices': [for (final n in notices) n.toJson()],
  };

  factory RetractionRecord.fromJson(Map<String, dynamic> j) => RetractionRecord(
    doi: j['doi'] as String,
    fetchedAt: DateTime.parse(j['fetchedAt'] as String),
    notices: [
      for (final n in j['notices'] as List)
        UpdateNotice.fromJson(n as Map<String, dynamic>),
    ],
  );
}

/// One JSON file per DOI in the cache folder (derived data: not synced,
/// not backed up), like `CitationCache`. [dir] may throw (no plugin under
/// `flutter test`); every method then behaves as an empty cache.
class RetractionCache {
  RetractionCache(this._dir, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final Future<Directory> Function() _dir;
  final DateTime Function() now;

  static const maxAge = Duration(days: 30);

  Future<File> _file(String doi) async {
    final name = doi.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.\-]'), '_');
    return File(p.join((await _dir()).path, '$name.json'));
  }

  /// Whether a cache folder is available at all.
  Future<bool> get available async {
    try {
      await _dir();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The cached record, however old; null if none or unreadable.
  Future<RetractionRecord?> read(String doi) async {
    try {
      final file = await _file(doi);
      if (!await file.exists()) return null;
      return RetractionRecord.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool isFresh(RetractionRecord r) => now().difference(r.fetchedAt) < maxAge;

  Future<void> write(RetractionRecord r) async {
    try {
      final file = await _file(r.doi);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(r.toJson()));
    } catch (_) {
      // A cache that can't be written is a miss next time.
    }
  }
}

/// Asks Crossref which notices update a DOI (https, no key, no personal
/// data). Failures throw [LookupFailed].
class RetractionClient {
  RetractionClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  Future<List<UpdateNotice>> notices(String doi) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.https('api.crossref.org', '/works', {
              'filter': 'updates:$doi',
              'rows': '20',
              'select': 'DOI,update-to,type,title,issued',
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const LookupFailed();
    }
    if (response.statusCode != 200) throw const LookupFailed();
    try {
      return parseUpdateNotices(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        doi,
      );
    } catch (_) {
      throw const LookupFailed();
    }
  }
}

/// Notice lookup with the cache in front: fresh (under 30 days) copies are
/// used as they are; offline, a stale copy beats nothing. With no cache
/// folder (tests, odd platforms) nothing is asked at all.
class RetractionService {
  RetractionService(this.client, this.cache);

  final RetractionClient client;
  final RetractionCache cache;

  /// Notices for [doi] (possibly empty), or null when unknown: nothing
  /// cached and Crossref unreachable. Never throws.
  Future<List<UpdateNotice>?> check(String doi, {bool refresh = false}) async {
    final key = normalizeCitationDoi(doi);
    if (key == null || !await cache.available) return null;
    final cached = await cache.read(key);
    if (!refresh && cached != null && cache.isFresh(cached)) {
      return cached.notices;
    }
    try {
      final found = await client.notices(key);
      await cache.write(
        RetractionRecord(doi: key, fetchedAt: cache.now(), notices: found),
      );
      return found;
    } catch (_) {
      return cached?.notices;
    }
  }

  /// Whatever is cached, any age. Never touches the network.
  Future<List<UpdateNotice>> cached(String doi) async {
    final key = normalizeCitationDoi(doi);
    if (key == null) return const [];
    return (await cache.read(key))?.notices ?? const [];
  }
}

final retractionCacheProvider = Provider<RetractionCache>(
  (ref) => RetractionCache(() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, 'retractions'));
  }),
);

final retractionClientProvider = Provider<RetractionClient>(
  (ref) => RetractionClient(),
);

final retractionServiceProvider = Provider<RetractionService>(
  (ref) => RetractionService(
    ref.watch(retractionClientProvider),
    ref.watch(retractionCacheProvider),
  ),
);

/// Cached notices only (Library list: never a network call per card).
final cachedNoticesProvider = FutureProvider.autoDispose
    .family<List<UpdateNotice>, String>(
      (ref, doi) => ref.watch(retractionServiceProvider).cached(doi),
    );

/// Checks (and caches) notices when a paper opens; refreshes the cached
/// view the Library list reads.
final noticeCheckProvider = FutureProvider.autoDispose
    .family<List<UpdateNotice>?, String>((ref, doi) async {
      final service = ref.watch(retractionServiceProvider);
      final found = await service.check(doi);
      if (found != null) ref.invalidate(cachedNoticesProvider(doi));
      return found;
    });

/// Fire-and-forget check after an import; never throws.
Future<void> checkNoticesInBackground(RetractionService service, String doi) =>
    service.check(doi).then<void>((_) {}, onError: (_) {});
