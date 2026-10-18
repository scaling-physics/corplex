import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'authors.dart';
import 'bibtex.dart' show PaperMetadata;
import 'metadata_lookup.dart';

/// One work as OpenAlex describes it: just what a reference list row needs.
class OpenAlexWork {
  const OpenAlexWork({
    required this.id,
    required this.title,
    this.authors = const [],
    this.year,
    this.venue,
    this.doi,
  });

  /// OpenAlex id, e.g. `W2741809807`.
  final String id;
  final String title;

  /// Display names, in order.
  final List<String> authors;
  final int? year;
  final String? venue;

  /// Bare DOI (no `https://doi.org/`), if the work has one.
  final String? doi;

  String get authorsLine => authors.isEmpty
      ? ''
      : authorsSummary(parseAuthors(authors.join('; ')), max: 2);

  /// What the existing add-a-paper path takes. arXiv works carry the
  /// arXiv DOI (`10.48550/arXiv.<id>`), kept as the DOI.
  PaperMetadata toMetadata() => PaperMetadata(
    title: title,
    authors: authors.isEmpty
        ? ''
        : authorsToStored(parseAuthors(authors.join('; '))),
    year: year,
    venue: venue,
    doi: doi,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'authors': authors,
    'year': year,
    'venue': venue,
    'doi': doi,
  };

  factory OpenAlexWork.fromJson(Map<String, dynamic> j) => OpenAlexWork(
    id: j['id'] as String,
    title: j['title'] as String,
    authors: [for (final a in (j['authors'] as List? ?? [])) a as String],
    year: j['year'] as int?,
    venue: j['venue'] as String?,
    doi: j['doi'] as String?,
  );
}

String _shortId(String id) => id.split('/').last;

/// Parses one OpenAlex work object (with the `select` fields used here).
/// Null for a work with no title.
OpenAlexWork? parseOpenAlexWork(Map<String, dynamic> j) {
  final title = (j['title'] ?? j['display_name']) as String?;
  final id = j['id'] as String?;
  if (title == null || title.trim().isEmpty || id == null) return null;
  final authors = <String>[
    for (final a in (j['authorships'] as List? ?? []))
      if (((a as Map)['author'] as Map?)?['display_name'] case final String n
          when n.trim().isNotEmpty)
        n.trim(),
  ];
  final venue =
      (((j['primary_location'] as Map?)?['source'] as Map?)?['display_name']
              as String?)
          ?.trim();
  return OpenAlexWork(
    id: _shortId(id),
    title: title.trim(),
    authors: authors,
    year: j['publication_year'] as int?,
    venue: venue == null || venue.isEmpty ? null : venue,
    doi: normalizeCitationDoi(j['doi'] as String?),
  );
}

/// Lower-case bare DOI, or null. Accepts doi.org links, and turns an arXiv
/// id into arXiv's DOI so both spellings of a paper compare equal.
String? normalizeCitationDoi(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final id = parseIdentifier(raw);
  if (id == null ||
      (id.kind != IdentifierKind.doi && id.kind != IdentifierKind.arxiv)) {
    return null;
  }
  final value = id.kind == IdentifierKind.arxiv
      ? '10.48550/arxiv.${id.value}'
      : id.value;
  return value.toLowerCase();
}

/// One "Cited by" page.
class CitedByPage {
  const CitedByPage(this.items, this.total);
  final List<OpenAlexWork> items;
  final int total;
}

/// Talks to OpenAlex (https, no key, no personal data: the request carries
/// no email or account). Failures throw [LookupFailed]; a work OpenAlex
/// doesn't know is null.
class OpenAlexClient {
  OpenAlexClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);
  static const _fields =
      'id,title,authorships,publication_year,primary_location,doi';
  static const batchSize = 50;
  static const pageSize = 25;

  /// The work behind [doi], with the ids of the works it cites.
  Future<({String id, String title, List<String> referenced, int citedBy})?>
  work(String doi) async {
    final uri = Uri.https(
      'api.openalex.org',
      '/works/doi:${Uri.encodeComponent(doi).replaceAll('%2F', '/')}',
      {'select': 'id,title,referenced_works,cited_by_count'},
    );
    final response = await _get(uri);
    if (response.statusCode == 404) return null;
    final j = _json(response);
    try {
      return (
        id: _shortId(j['id'] as String),
        title: (j['title'] as String?) ?? '',
        referenced: [
          for (final r in (j['referenced_works'] as List? ?? []))
            _shortId(r as String),
        ],
        citedBy: (j['cited_by_count'] as int?) ?? 0,
      );
    } catch (_) {
      throw const LookupFailed();
    }
  }

  /// Resolves OpenAlex ids to works, keeping [ids]' order. Ids OpenAlex
  /// can't resolve are left out.
  Future<List<OpenAlexWork>> worksByIds(List<String> ids) async {
    final byId = <String, OpenAlexWork>{};
    for (var i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(i, (i + batchSize).clamp(0, ids.length));
      final j = _json(
        await _get(
          Uri.https('api.openalex.org', '/works', {
            'filter': 'openalex_id:${chunk.join('|')}',
            'per-page': '$batchSize',
            'select': _fields,
          }),
        ),
      );
      for (final w in _results(j)) {
        byId[w.id] = w;
      }
    }
    return [for (final id in ids) ?byId[id]];
  }

  /// A page (1-based) of works citing [workId], most cited first.
  Future<CitedByPage> citedBy(String workId, {int page = 1}) async {
    final j = _json(
      await _get(
        Uri.https('api.openalex.org', '/works', {
          'filter': 'cites:$workId',
          'sort': 'cited_by_count:desc',
          'per-page': '$pageSize',
          'page': '$page',
          'select': _fields,
        }),
      ),
    );
    final total = ((j['meta'] as Map?)?['count'] as int?) ?? 0;
    return CitedByPage(_results(j), total);
  }

  List<OpenAlexWork> _results(Map<String, dynamic> j) {
    try {
      return [
        for (final r in (j['results'] as List? ?? []))
          ?parseOpenAlexWork(r as Map<String, dynamic>),
      ];
    } catch (_) {
      throw const LookupFailed();
    }
  }

  Map<String, dynamic> _json(http.Response response) {
    if (response.statusCode != 200) throw const LookupFailed();
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const LookupFailed();
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } catch (_) {
      throw const LookupFailed();
    }
  }
}

/// A paper's references and citing works, as cached.
class CitationRecord {
  CitationRecord({
    required this.doi,
    required this.fetchedAt,
    required this.workId,
    required this.references,
    required this.referenceCount,
    required this.cited,
    required this.citedTotal,
  });

  final String doi;
  final DateTime fetchedAt;
  final String workId;

  /// The references OpenAlex could resolve (capped, see
  /// [CitationNetwork.maxReferences]).
  final List<OpenAlexWork> references;

  /// How many works the paper lists as references, resolved or not.
  final int referenceCount;
  final List<OpenAlexWork> cited;
  final int citedTotal;

  bool get hasMoreCited => cited.length < citedTotal;

  CitationRecord copyWith({List<OpenAlexWork>? cited}) => CitationRecord(
    doi: doi,
    fetchedAt: fetchedAt,
    workId: workId,
    references: references,
    referenceCount: referenceCount,
    cited: cited ?? this.cited,
    citedTotal: citedTotal,
  );

  Map<String, dynamic> toJson() => {
    'doi': doi,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'workId': workId,
    'references': [for (final w in references) w.toJson()],
    'referenceCount': referenceCount,
    'cited': [for (final w in cited) w.toJson()],
    'citedTotal': citedTotal,
  };

  factory CitationRecord.fromJson(Map<String, dynamic> j) => CitationRecord(
    doi: j['doi'] as String,
    fetchedAt: DateTime.parse(j['fetchedAt'] as String),
    workId: j['workId'] as String,
    references: [
      for (final w in j['references'] as List)
        OpenAlexWork.fromJson(w as Map<String, dynamic>),
    ],
    referenceCount: j['referenceCount'] as int,
    cited: [
      for (final w in j['cited'] as List)
        OpenAlexWork.fromJson(w as Map<String, dynamic>),
    ],
    citedTotal: j['citedTotal'] as int,
  );
}

/// JSON files in the app's cache folder: derived data, so never synced and
/// not part of backups. One file per DOI.
class CitationCache {
  CitationCache(this._dir, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final Future<Directory> Function() _dir;
  final DateTime Function() now;

  static const maxAge = Duration(days: 30);

  Future<File> _file(String doi) async {
    final name = doi.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.\-]'), '_');
    return File(p.join((await _dir()).path, '$name.json'));
  }

  /// The cached record, however old; null if none or unreadable.
  Future<CitationRecord?> read(String doi) async {
    try {
      final file = await _file(doi);
      if (!await file.exists()) return null;
      return CitationRecord.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  bool isFresh(CitationRecord r) => now().difference(r.fetchedAt) < maxAge;

  Future<void> write(CitationRecord r) async {
    try {
      final file = await _file(r.doi);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(r.toJson()));
    } catch (_) {
      // A cache that can't be written is just a cache miss next time.
    }
  }
}

/// Fetching with the cache in front.
class CitationNetwork {
  CitationNetwork(this.client, this.cache);

  final OpenAlexClient client;
  final CitationCache cache;

  /// More references than this are listed by count only.
  static const maxReferences = 200;

  /// References and first page of citing works for [doi]. Uses the cache
  /// while it is under 30 days old unless [refresh]; when the network is
  /// unreachable, an older cached copy beats an error (unless [refresh]).
  /// Null if OpenAlex doesn't know the DOI. Throws [LookupFailed].
  Future<CitationRecord?> load(String doi, {bool refresh = false}) async {
    final key = normalizeCitationDoi(doi);
    if (key == null) return null;
    final cached = await cache.read(key);
    if (!refresh && cached != null && cache.isFresh(cached)) return cached;
    try {
      final work = await client.work(key);
      if (work == null) return null;
      final ids = work.referenced.take(maxReferences).toList();
      final refs = ids.isEmpty
          ? <OpenAlexWork>[]
          : await client.worksByIds(ids);
      final cited = await client.citedBy(work.id);
      final record = CitationRecord(
        doi: key,
        fetchedAt: cache.now(),
        workId: work.id,
        references: refs,
        referenceCount: work.referenced.length,
        cited: cited.items,
        citedTotal: cited.total,
      );
      await cache.write(record);
      return record;
    } on LookupFailed {
      if (!refresh && cached != null) return cached;
      rethrow;
    }
  }

  /// The next page of citing works, appended and cached.
  Future<CitationRecord> loadMoreCited(CitationRecord r) async {
    final page = r.cited.length ~/ OpenAlexClient.pageSize + 1;
    final next = await client.citedBy(r.workId, page: page);
    final known = {for (final w in r.cited) w.id};
    final updated = r.copyWith(
      cited: [
        ...r.cited,
        for (final w in next.items)
          if (known.add(w.id)) w,
      ],
    );
    await cache.write(updated);
    return updated;
  }

  /// DOIs of the cached references (any age); empty when nothing is cached.
  /// Never touches the network.
  Future<Set<String>> cachedReferenceDois(String doi) async {
    final key = normalizeCitationDoi(doi);
    if (key == null) return const {};
    final r = await cache.read(key);
    return {
      if (r != null)
        for (final w in r.references)
          if (w.doi != null) w.doi!,
    };
  }
}

final citationCacheProvider = Provider<CitationCache>(
  (ref) => CitationCache(() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, 'openalex'));
  }),
);

final openAlexClientProvider = Provider<OpenAlexClient>(
  (ref) => OpenAlexClient(),
);

final citationNetworkProvider = Provider<CitationNetwork>(
  (ref) => CitationNetwork(
    ref.watch(openAlexClientProvider),
    ref.watch(citationCacheProvider),
  ),
);
