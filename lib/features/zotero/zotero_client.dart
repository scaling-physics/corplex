import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Why a Zotero request failed, in words a reader can act on.
enum ZoteroProblem { badKey, notFound, rateLimited, offline, server }

class ZoteroException implements Exception {
  const ZoteroException(this.problem, [this.detail]);

  final ZoteroProblem problem;
  final String? detail;

  String get message => switch (problem) {
    ZoteroProblem.badKey =>
      'Zotero didn\'t accept that user ID and key. Check both, and that the '
          'key is allowed to read your library.',
    ZoteroProblem.notFound =>
      'Zotero couldn\'t find that library. Check the user ID '
          '(the number on zotero.org/settings/keys).',
    ZoteroProblem.rateLimited =>
      'Zotero is asking for a pause. Try again in a few minutes.',
    ZoteroProblem.offline =>
      'Couldn\'t reach Zotero. Check your connection and try again.',
    ZoteroProblem.server =>
      'Zotero had a problem${detail == null ? '' : ' ($detail)'}. '
          'Try again later.',
  };

  @override
  String toString() => 'ZoteroException($problem, $detail)';
}

/// A minimal Zotero Web API v3 client. Everything is https, read-only, and
/// the key never leaves the `Zotero-API-Key` header.
class ZoteroClient {
  ZoteroClient({
    required this.userId,
    required this.apiKey,
    http.Client? client,
    this.maxFileBytes = 50 * 1024 * 1024,
    Future<void> Function(Duration)? delay,
    this.maxRetries = 3,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? Future.delayed;

  final String userId;
  final String apiKey;
  final int maxFileBytes;
  final int maxRetries;
  final http.Client _client;
  final Future<void> Function(Duration) _delay;

  static const host = 'api.zotero.org';
  static const pageSize = 100;

  /// Don't send another request before this moment (a `Backoff` header).
  DateTime? _notBefore;

  Map<String, String> get _headers => {
    'Zotero-API-Version': '3',
    'Zotero-API-Key': apiKey,
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.https(host, '/users/${Uri.encodeComponent(userId)}$path', query);

  Future<http.Response> _send(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      final wait = _notBefore?.difference(DateTime.now());
      if (wait != null && !wait.isNegative) await _delay(wait);
      http.Response res;
      try {
        res = await _client.get(uri, headers: _headers);
      } on SocketException {
        throw const ZoteroException(ZoteroProblem.offline);
      } on http.ClientException {
        throw const ZoteroException(ZoteroProblem.offline);
      } on TimeoutException {
        throw const ZoteroException(ZoteroProblem.offline);
      }
      final backoff = int.tryParse(res.headers['backoff'] ?? '');
      if (backoff != null) {
        _notBefore = DateTime.now().add(Duration(seconds: backoff));
      }
      if (res.statusCode == 429 || res.statusCode == 503) {
        final retry = int.tryParse(res.headers['retry-after'] ?? '') ?? 5;
        if (attempt >= maxRetries) {
          throw const ZoteroException(ZoteroProblem.rateLimited);
        }
        await _delay(Duration(seconds: retry));
        continue;
      }
      switch (res.statusCode) {
        case 200:
          return res;
        case 401 || 403:
          throw const ZoteroException(ZoteroProblem.badKey);
        case 404:
          throw const ZoteroException(ZoteroProblem.notFound);
        default:
          throw ZoteroException(ZoteroProblem.server, '${res.statusCode}');
      }
    }
  }

  /// Every object under [path], following `start`/`limit` pages until
  /// `Total-Results` (or a short page) says there are no more. [onPage]
  /// reports `(fetched, total)`.
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String> query = const {},
    void Function(int fetched, int? total)? onPage,
  }) async {
    final out = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final res = await _send(
        _uri(path, {...query, 'limit': '$pageSize', 'start': '$start'}),
      );
      final List<dynamic> page;
      try {
        page = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      } catch (_) {
        throw const ZoteroException(ZoteroProblem.server, 'unreadable reply');
      }
      out.addAll(page.whereType<Map<String, dynamic>>());
      start += page.length;
      final total = int.tryParse(res.headers['total-results'] ?? '');
      onPage?.call(out.length, total);
      final more = total != null
          ? start < total
          : (res.headers['link'] ?? '').contains('rel="next"');
      if (page.isEmpty || !more) return out;
    }
  }

  /// A cheap call that proves the id and key work.
  Future<void> check() => _send(_uri('/collections', {'limit': '1'}));

  Future<List<Map<String, dynamic>>> collections({
    void Function(int, int?)? onPage,
  }) => getAll('/collections', onPage: onPage);

  /// Top-level items: no child notes or attachments.
  Future<List<Map<String, dynamic>>> topItems({
    void Function(int, int?)? onPage,
  }) =>
      getAll('/items/top', query: {'itemType': '-attachment'}, onPage: onPage);

  /// All items of [itemType] (attachment, annotation, note), children
  /// included, in one paged request instead of one per paper.
  Future<List<Map<String, dynamic>>> itemsOfType(
    String itemType, {
    void Function(int, int?)? onPage,
  }) => getAll('/items', query: {'itemType': itemType}, onPage: onPage);

  /// The attachment's file, or null when it is over [maxFileBytes] or the
  /// file isn't stored in Zotero (404). Redirects to storage are followed
  /// by the HTTP client.
  Future<Uint8List?> downloadFile(String itemKey) async {
    try {
      final res = await _send(_uri('/items/$itemKey/file'));
      final declared = int.tryParse(res.headers['content-length'] ?? '');
      if ((declared ?? 0) > maxFileBytes ||
          res.bodyBytes.length > maxFileBytes) {
        return null;
      }
      return res.bodyBytes;
    } on ZoteroException catch (e) {
      if (e.problem == ZoteroProblem.notFound) return null;
      rethrow;
    }
  }

  void close() => _client.close();
}
