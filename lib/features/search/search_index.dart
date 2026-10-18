import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_crypto.dart';
import 'note_search_text.dart';

enum SearchKind { note, paper, highlight, pdfText }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.snippet,
    this.locked = false,
    this.paperId,
    this.page,
  });

  final SearchKind kind;

  /// The note / paper / highlight id.
  final String id;
  final String title;

  /// A short excerpt around the match, with `⟦…⟧` around matched words.
  final String snippet;

  /// A locked note: found by title only, never by its body.
  final bool locked;

  /// For highlights: the paper it belongs to and its page.
  final String? paperId;
  final int? page;
}

const _open = '⟦';
const _close = '⟧';

/// Full-text search over notes, papers and highlights using SQLite FTS5.
///
/// The index is a virtual table kept beside the data, not part of the
/// synced schema: it's derived, so every device rebuilds its own. It stays
/// current by comparing each row's `updated_at` with the stamp it was
/// indexed at, so notes changed by a sync are picked up too, and only
/// changed rows are re-read (note content is Quill JSON and must be turned
/// into text in Dart, which is why triggers can't do this).
class SearchIndex {
  SearchIndex(this._db);

  final AppDatabase _db;
  bool? _available;

  /// Whether this SQLite build has FTS5; if not, [search] falls back to a
  /// plain substring scan.
  Future<bool> get available async {
    if (_available != null) return _available!;
    try {
      await _db.customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
        'kind UNINDEXED, ref UNINDEXED, stamp UNINDEXED, aux UNINDEXED, '
        "title, body, tokenize = 'unicode61 remove_diacritics 2')",
      );
      return _available = true;
    } catch (_) {
      return _available = false;
    }
  }

  /// Brings the index up to date. Cheap when nothing changed.
  Future<void> refresh() async {
    if (!await available) return;
    await _db.transaction(() async {
      await _sync(
        SearchKind.note,
        // The stamp carries "locked" in its low bit, so locking a note
        // re-indexes it even if `updated_at` somehow didn't move, and the
        // old plain text leaves the table. A locked note is indexed by
        // title only: its body is an envelope (or, before the lock, text).
        "SELECT id, updated_at * 2 + (content LIKE '$lockedPrefix%') "
        'AS updated_at, title, content AS body, '
        "CASE WHEN content LIKE '$lockedPrefix%' THEN 'locked' END AS aux "
        'FROM notes',
        (row) => (
          title: row.read<String>('title'),
          body: row.read<String?>('aux') == 'locked'
              ? ''
              : noteSearchText(row.read<String>('body')),
        ),
      );
      await _sync(
        SearchKind.paper,
        'SELECT id, updated_at, title, '
        "authors || ' ' || COALESCE(venue, '') || ' ' || COALESCE(doi, '') "
        "|| ' ' || COALESCE(species, '') || ' ' || COALESCE(brain_regions, '') "
        "|| ' ' || COALESCE(techniques, '') || ' ' || COALESCE(paradigm, '') "
        'AS body, NULL AS aux FROM papers',
        (row) =>
            (title: row.read<String>('title'), body: row.read<String>('body')),
      );
      await _sync(
        SearchKind.highlight,
        "SELECT id, updated_at, quote AS title, COALESCE(comment, '') AS body, "
        "paper_id || '|' || page_number AS aux FROM highlights",
        (row) =>
            (title: row.read<String>('title'), body: row.read<String>('body')),
      );
    });
  }

  Future<void> _sync(
    SearchKind kind,
    String selectSql,
    ({String title, String body}) Function(QueryRow row) extract,
  ) async {
    final rows = await _db.customSelect(selectSql).get();
    final indexed = {
      for (final r
          in await _db
              .customSelect(
                'SELECT ref, stamp FROM search_index WHERE kind = ?',
                variables: [Variable.withString(kind.name)],
              )
              .get())
        r.read<String>('ref'): r.read<int>('stamp'),
    };

    final seen = <String>{};
    for (final row in rows) {
      final id = row.read<String>('id');
      final stamp = row.read<int>('updated_at');
      seen.add(id);
      if (indexed[id] == stamp) continue;
      final text = extract(row);
      await _remove(kind, id);
      await _db.customStatement(
        'INSERT INTO search_index (kind, ref, stamp, aux, title, body) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [kind.name, id, stamp, row.read<String?>('aux'), text.title, text.body],
      );
    }
    for (final gone in indexed.keys.where((id) => !seen.contains(id))) {
      await _remove(kind, gone);
    }
  }

  Future<void> _remove(SearchKind kind, String id) => _db.customStatement(
    'DELETE FROM search_index WHERE kind = ? AND ref = ?',
    [kind.name, id],
  );

  /// Results for [query], best matches first, at most [limit] per kind.
  /// Words match as prefixes ("trans" finds "transformer"); several words
  /// must all appear.
  Future<List<SearchHit>> search(String query, {int limit = 20}) async {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];
    if (!await available) return _scan(terms, limit);

    await refresh();
    final match = terms.map((t) => '"$t"*').join(' ');
    final hits = <SearchHit>[];
    for (final kind in SearchKind.values) {
      // Paper text lives in its own index (PdfTextIndex).
      if (kind == SearchKind.pdfText) continue;
      final rows = await _db
          .customSelect(
            'SELECT ref, aux, title, '
            "snippet(search_index, 5, '$_open', '$_close', '…', 14) AS snip, "
            "highlight(search_index, 4, '$_open', '$_close') AS marked_title, "
            'body FROM search_index '
            'WHERE search_index MATCH ? AND kind = ? '
            // Title matches count double.
            'ORDER BY bm25(search_index, 0, 0, 0, 0, 2.0, 1.0) LIMIT ?',
            variables: [
              Variable.withString(match),
              Variable.withString(kind.name),
              Variable.withInt(limit),
            ],
          )
          .get();
      for (final row in rows) {
        final aux = row.read<String?>('aux');
        final locked = kind == SearchKind.note && aux == 'locked';
        final split = locked ? null : aux?.split('|');
        final body = row.read<String>('body');
        hits.add(
          SearchHit(
            kind: kind,
            id: row.read<String>('ref'),
            title: row.read<String>('marked_title'),
            // A match in the title alone leaves the body snippet unmarked;
            // that's fine — it still shows the start of the text.
            snippet: locked
                ? 'Locked'
                : body.isEmpty
                ? ''
                : row.read<String>('snip'),
            locked: locked,
            paperId: split?.first,
            page: split == null ? null : int.tryParse(split.last),
          ),
        );
      }
    }
    return hits;
  }

  /// FTS5 syntax characters would be misread; keep words and digits only.
  static List<String> _terms(String query) => RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(query.toLowerCase()).map((m) => m.group(0)!).toList();

  /// Fallback when FTS5 isn't compiled in: substring match over everything.
  Future<List<SearchHit>> _scan(List<String> terms, int limit) async {
    bool matches(String text) {
      final lower = text.toLowerCase();
      return terms.every(lower.contains);
    }

    final hits = <SearchHit>[];
    for (final n in await _db.select(_db.notes).get()) {
      final locked = isLockedContent(n.content);
      final body = locked ? '' : noteSearchText(n.content);
      if (matches('${n.title} $body')) {
        hits.add(
          SearchHit(
            kind: SearchKind.note,
            id: n.id,
            title: n.title,
            snippet: locked ? 'Locked' : body,
            locked: locked,
          ),
        );
      }
    }
    for (final p in await _db.select(_db.papers).get()) {
      final body =
          '${p.authors} ${p.venue ?? ''} ${p.doi ?? ''} '
          '${p.species ?? ''} ${p.brainRegions ?? ''} ${p.techniques ?? ''} '
          '${p.paradigm ?? ''}';
      if (matches('${p.title} $body')) {
        hits.add(
          SearchHit(
            kind: SearchKind.paper,
            id: p.id,
            title: p.title,
            snippet: body,
          ),
        );
      }
    }
    for (final h in await _db.select(_db.highlights).get()) {
      if (matches('${h.quote} ${h.comment ?? ''}')) {
        hits.add(
          SearchHit(
            kind: SearchKind.highlight,
            id: h.id,
            title: h.quote,
            snippet: h.comment ?? '',
            paperId: h.paperId,
            page: h.pageNumber,
          ),
        );
      }
    }
    return hits;
  }
}

final searchIndexProvider = Provider<SearchIndex>(
  (ref) => SearchIndex(ref.watch(databaseProvider)),
);

/// The words to emphasize in a snippet produced by [SearchIndex.search].
List<({String text, bool match})> splitMarked(String marked) {
  final parts = <({String text, bool match})>[];
  var i = 0;
  while (i < marked.length) {
    final start = marked.indexOf(_open, i);
    if (start < 0) {
      parts.add((text: marked.substring(i), match: false));
      break;
    }
    if (start > i) parts.add((text: marked.substring(i, start), match: false));
    final end = marked.indexOf(_close, start);
    if (end < 0) {
      parts.add((text: marked.substring(start + 1), match: false));
      break;
    }
    parts.add((text: marked.substring(start + 1, end), match: true));
    i = end + 1;
  }
  return parts;
}
