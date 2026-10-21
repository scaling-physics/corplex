import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_crypto.dart';
import 'note_search_text.dart';
import 'search_filters.dart';
import 'search_query.dart';

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
  /// [useFts] false behaves as a SQLite without FTS5 (for tests).
  SearchIndex(this._db, {@visibleForTesting bool useFts = true})
    : _available = useFts ? null : false;

  final AppDatabase _db;
  bool? _available;

  /// Whether this SQLite build has FTS5; if not, [search] falls back to a
  /// plain substring scan.
  Future<bool> get available async {
    if (_available != null) return _available!;
    try {
      final existed = await _db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE name = 'search_index'",
          )
          .get();
      await _db.customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5('
        'kind UNINDEXED, ref UNINDEXED, stamp UNINDEXED, aux UNINDEXED, '
        "title, body, tokenize = 'unicode61 remove_diacritics 2')",
      );
      // What is indexed, in a plain table with a primary key: diffing the
      // index against the data would otherwise scan the FTS table (bodies
      // and all) on every search. `fts_rowid` is the row's rowid in
      // `search_index`.
      await _db.customStatement(
        'CREATE TABLE IF NOT EXISTS search_state ('
        'fts_rowid INTEGER PRIMARY KEY, kind TEXT NOT NULL, '
        'ref TEXT NOT NULL, stamp INTEGER NOT NULL, UNIQUE (kind, ref))',
      );
      // The two must agree. A backup drops `search_index` (and a fresh
      // install has neither): start over rather than trust stale state.
      if (existed.isEmpty) {
        await _db.customStatement('DELETE FROM search_state');
      } else {
        final state = await _db
            .customSelect('SELECT 1 FROM search_state LIMIT 1')
            .get();
        if (state.isEmpty) {
          // An index from before `search_state` existed: rebuild it.
          await _db.customStatement('DELETE FROM search_index');
        }
      }
      return _available = true;
    } catch (_) {
      return _available = false;
    }
  }

  /// Brings the index up to date. Cheap when nothing changed: it compares
  /// ids and stamps only (never the note bodies), and re-reads just the
  /// rows whose stamp moved. Concurrent callers (every keystroke asks) share
  /// one pass.
  Future<void> refresh() async {
    _watchWrites();
    // Table-update notifications arrive on the event loop; let one that a
    // just-finished write queued land before deciding nothing changed.
    await Future<void>.delayed(Duration.zero);
    return _refreshNow();
  }

  Future<void> _refreshNow() {
    final running = _refreshing;
    // Nothing was written to the indexed tables since the last pass.
    if (running == null && !_dirty) return Future.value();
    if (running == null) return _startRefresh();
    // A pass that started before this call may have missed this call's
    // changes: run one more straight after it, shared by every waiter that
    // arrives before it starts.
    return _queued ??= running.catchError((Object _) {}).then((_) {
      _queued = null;
      return _startRefresh();
    });
  }

  /// Set whenever drift sees a write to a table the index is built from
  /// (including the sync engine's, which announces its raw SQL), so a search
  /// with no edits in between skips the comparison entirely.
  bool _dirty = true;
  StreamSubscription<Set<TableUpdate>>? _writes;

  void _watchWrites() {
    _writes ??= _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([_db.notes, _db.papers, _db.highlights]),
        )
        .listen((_) => _dirty = true);
  }

  /// Stops watching for writes; the index stays correct but every
  /// [refresh] compares again.
  void dispose() {
    _writes?.cancel();
    _writes = null;
    _dirty = true;
  }

  Future<void>? _refreshing;
  Future<void>? _queued;

  Future<void> _startRefresh() {
    // Writes that land during the pass set this again.
    _dirty = false;
    final pass = _refresh().catchError((Object e) {
      _dirty = true;
      throw e;
    });
    late final Future<void> tracked;
    tracked = pass.whenComplete(() {
      if (identical(_refreshing, tracked)) _refreshing = null;
    });
    return _refreshing = tracked;
  }

  Future<void> _refresh() async {
    if (!await available) return;
    _nextRowid =
        ((await _db
                .customSelect(
                  'SELECT COALESCE(MAX(fts_rowid), 0) + 1 AS n FROM search_state',
                )
                .getSingle())
            .read<int>('n'));
    // The stamp carries "locked" in its low bit, so locking a note
    // re-indexes it even if `updated_at` somehow didn't move, and the
    // old plain text leaves the table. A locked note is indexed by
    // title only: its body is an envelope (or, before the lock, text).
    await _sync(
      SearchKind.note,
      'notes',
      "updated_at * 2 + (content LIKE '$lockedPrefix%')",
      "SELECT id, updated_at * 2 + (content LIKE '$lockedPrefix%') "
          'AS updated_at, title, aliases, content AS body, '
          "CASE WHEN content LIKE '$lockedPrefix%' THEN 'locked' END AS aux "
          'FROM notes',
      (row) => (
        title: indexedNoteTitle(
          row.read<String>('title'),
          row.read<String?>('aliases'),
        ),
        body: row.read<String?>('aux') == 'locked'
            ? ''
            : noteSearchText(row.read<String>('body')),
      ),
    );
    await _sync(
      SearchKind.paper,
      'papers',
      'updated_at',
      'SELECT id, updated_at, title, '
          "authors || ' ' || COALESCE(venue, '') || ' ' || COALESCE(doi, '') "
          "|| ' ' || COALESCE(species, '') || ' ' || COALESCE(brain_regions, '') "
          "|| ' ' || COALESCE(techniques, '') || ' ' || COALESCE(paradigm, '') "
          "|| ' ' || COALESCE(abstract, '') "
          'AS body, NULL AS aux FROM papers',
      (row) =>
          (title: row.read<String>('title'), body: row.read<String>('body')),
    );
    await _sync(
      SearchKind.highlight,
      'highlights',
      'updated_at',
      "SELECT id, updated_at, quote AS title, COALESCE(comment, '') AS body, "
          "paper_id || '|' || page_number AS aux FROM highlights",
      (row) =>
          (title: row.read<String>('title'), body: row.read<String>('body')),
    );
  }

  int _nextRowid = 1;

  /// Rows re-read and indexed per transaction (and per yield to the UI).
  static const _chunk = 40;

  Future<void> _sync(
    SearchKind kind,
    String table,
    String stampSql,
    String selectSql,
    ({String title, String body}) Function(QueryRow row) extract,
  ) async {
    // The comparison happens in SQLite, against the plain `search_state`
    // table and never the note bodies: only rows that are new or whose
    // stamp moved come back, with the rowid they had.
    final indexed = <String, ({int rowid, int stamp})>{};
    final changed = <String>[];
    for (final r
        in await _db
            .customSelect(
              'SELECT t.id AS id, s.fts_rowid AS rowid, s.stamp AS stamp '
              'FROM $table t LEFT JOIN search_state s '
              'ON s.kind = ? AND s.ref = t.id '
              'WHERE s.stamp IS NOT ($stampSql)',
              variables: [Variable.withString(kind.name)],
            )
            .get()) {
      final id = r.read<String>('id');
      changed.add(id);
      final rowid = r.read<int?>('rowid');
      if (rowid != null) {
        indexed[id] = (rowid: rowid, stamp: r.read<int>('stamp'));
      }
    }
    final gone = [
      for (final r
          in await _db
              .customSelect(
                'SELECT fts_rowid AS rowid FROM search_state '
                'WHERE kind = ? AND ref NOT IN (SELECT id FROM $table)',
                variables: [Variable.withString(kind.name)],
              )
              .get())
        r.read<int>('rowid'),
    ];
    if (gone.isEmpty && changed.isEmpty) return;

    // A batch is one message to the database isolate (and one
    // transaction), not a round trip per statement: those dominated a first
    // build on a phone.
    if (gone.isNotEmpty) {
      await _db.batch((b) {
        for (final rowid in gone) {
          b.customStatement('DELETE FROM search_index WHERE rowid = ?', [
            rowid,
          ]);
          b.customStatement('DELETE FROM search_state WHERE fts_rowid = ?', [
            rowid,
          ]);
        }
      });
    }
    for (var start = 0; start < changed.length; start += _chunk) {
      final ids = changed.sublist(
        start,
        start + _chunk > changed.length ? changed.length : start + _chunk,
      );
      final rows = await _db
          .customSelect(
            '$selectSql WHERE id IN (${List.filled(ids.length, '?').join(',')})',
            variables: [for (final id in ids) Variable.withString(id)],
          )
          .get();
      // Text extraction is the expensive part (Quill JSON); do it before
      // taking the write lock.
      final prepared = [
        for (final row in rows)
          (
            id: row.read<String>('id'),
            stamp: row.read<int>('updated_at'),
            aux: row.read<String?>('aux'),
            text: extract(row),
          ),
      ];
      await _db.batch((b) {
        for (final item in prepared) {
          final old = indexed[item.id];
          // An edited row keeps its rowid; a new one takes the next.
          final rowid = old?.rowid ?? _nextRowid++;
          if (old != null) {
            b.customStatement('DELETE FROM search_index WHERE rowid = ?', [
              rowid,
            ]);
          }
          b.customStatement(
            'INSERT INTO search_index '
            '(rowid, kind, ref, stamp, aux, title, body) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              rowid,
              kind.name,
              item.id,
              item.stamp,
              item.aux,
              item.text.title,
              item.text.body,
            ],
          );
          b.customStatement(
            'INSERT OR REPLACE INTO search_state (fts_rowid, kind, ref, stamp) '
            'VALUES (?, ?, ?, ?)',
            [rowid, kind.name, item.id, item.stamp],
          );
        }
      });
      // A first build is thousands of notes: let frames through.
      if (start + _chunk < changed.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Results for [query] (see [parseSearchQuery] for the operators), best
  /// matches first, at most [limit] per kind. Words match as prefixes
  /// ("trans" finds "transformer"); several words must all appear.
  Future<List<SearchHit>> search(String query, {int limit = 20}) =>
      searchParsed(parseSearchQuery(query), limit: limit);

  /// [search] for an already parsed query. Papers' own text (`pdfs`) lives
  /// in another index and isn't searched here.
  Future<List<SearchHit>> searchParsed(
    SearchQuery query, {
    int limit = 20,
  }) async {
    if (query.isEmpty) return const [];
    if (!await available) return _scan(query, limit);

    await refresh();
    final match = query.ftsMatch;
    final hits = <SearchHit>[];
    for (final kind in SearchKind.values) {
      // Paper text lives in its own index (PdfTextIndex).
      if (kind == SearchKind.pdfText) continue;
      final filter = searchFilterSql(query, kind, 'ref');
      if (filter == null) continue;
      if (match == null) {
        // Nothing to look up (only exclusions and filters): read the
        // candidates and test them here.
        hits.addAll(await _scanIndexed(query, kind, filter, limit));
        continue;
      }
      final rows = await _db
          .customSelect(
            'SELECT ref, aux, title, '
            "snippet(search_index, 5, '$_open', '$_close', '…', 14) AS snip, "
            "highlight(search_index, 4, '$_open', '$_close') AS marked_title, "
            "(body = '') AS body_empty FROM search_index "
            'WHERE search_index MATCH ? AND kind = ? '
            '${filter.isEmpty ? '' : 'AND ${filter.where} '}'
            // Title matches count double.
            'ORDER BY bm25(search_index, 0, 0, 0, 0, 2.0, 1.0) LIMIT ?',
            variables: [
              Variable.withString(match),
              Variable.withString(kind.name),
              ...filter.variables,
              Variable.withInt(limit),
            ],
          )
          .get();
      for (final row in rows) {
        final aux = row.read<String?>('aux');
        final locked = kind == SearchKind.note && aux == 'locked';
        final split = locked ? null : aux?.split('|');
        final bodyEmpty = row.read<int>('body_empty') != 0;
        hits.add(
          SearchHit(
            kind: kind,
            id: row.read<String>('ref'),
            title: displayIndexedTitle(row.read<String>('marked_title')),
            // A match in the title alone leaves the body snippet unmarked;
            // that's fine — it still shows the start of the text.
            snippet: locked
                ? 'Locked'
                : bodyEmpty
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

  /// Candidates of [kind] read from the index table itself, kept when
  /// [query] matches their text: for queries FTS can't express alone.
  Future<List<SearchHit>> _scanIndexed(
    SearchQuery query,
    SearchKind kind,
    SearchFilterSql filter,
    int limit,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT ref, aux, title, body FROM search_index WHERE kind = ? '
          '${filter.isEmpty ? '' : 'AND ${filter.where}'}',
          variables: [Variable.withString(kind.name), ...filter.variables],
        )
        .get();
    final hits = <SearchHit>[];
    for (final row in rows) {
      final title = displayIndexedTitle(row.read<String>('title'));
      final body = row.read<String>('body');
      if (!query.matchesText(
        row.read<String>('title').replaceAll(_aliasSeparator, ' '),
        body,
      )) {
        continue;
      }
      final aux = row.read<String?>('aux');
      final locked = kind == SearchKind.note && aux == 'locked';
      final split = locked ? null : aux?.split('|');
      hits.add(
        SearchHit(
          kind: kind,
          id: row.read<String>('ref'),
          title: title,
          snippet: locked ? 'Locked' : _excerpt(body),
          locked: locked,
          paperId: split?.first,
          page: split == null ? null : int.tryParse(split.last),
        ),
      );
      if (hits.length >= limit) break;
    }
    return hits;
  }

  static String _excerpt(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 140 ? text : '${text.substring(0, 140)}…';
  }

  /// Ids of [kind] rows satisfying [query]'s filters (null = none can).
  Future<Set<String>?> _allowedIds(
    SearchQuery query,
    SearchKind kind,
    String table,
  ) async {
    final filter = searchFilterSql(query, kind, 'id');
    if (filter == null) return null;
    final rows = await _db
        .customSelect(
          'SELECT id FROM $table '
          '${filter.isEmpty ? '' : 'WHERE ${filter.where}'}',
          variables: filter.variables,
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  /// Fallback when FTS5 isn't compiled in: substring match over everything,
  /// with the same operators.
  Future<List<SearchHit>> _scan(SearchQuery query, int limit) async {
    final hits = <SearchHit>[];
    final noteIds = await _allowedIds(query, SearchKind.note, 'notes');
    if (noteIds != null) {
      for (final n in await _db.select(_db.notes).get()) {
        if (!noteIds.contains(n.id)) continue;
        final locked = isLockedContent(n.content);
        final body = locked ? '' : noteSearchText(n.content);
        final aliases = n.aliases ?? '';
        if (query.matchesText('${n.title} $aliases', body)) {
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
    }
    final paperIds = await _allowedIds(query, SearchKind.paper, 'papers');
    if (paperIds != null) {
      for (final p in await _db.select(_db.papers).get()) {
        if (!paperIds.contains(p.id)) continue;
        final body =
            '${p.authors} ${p.venue ?? ''} ${p.doi ?? ''} '
            '${p.species ?? ''} ${p.brainRegions ?? ''} ${p.techniques ?? ''} '
            '${p.paradigm ?? ''} ${p.abstract ?? ''}';
        if (query.matchesText(p.title, body)) {
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
    }
    final highlightIds = await _allowedIds(
      query,
      SearchKind.highlight,
      'highlights',
    );
    if (highlightIds != null) {
      for (final h in await _db.select(_db.highlights).get()) {
        if (!highlightIds.contains(h.id)) continue;
        if (query.matchesText(h.quote, h.comment ?? '')) {
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
    }
    return hits;
  }
}

/// Separates a note's title from its aliases in the index's title column
/// (a control character: the tokenizer treats it as a word break, and it
/// can't be typed into a title).
const _aliasSeparator = '\u001F';

/// The index's title text for a note: the title, then its aliases, so a
/// note is found by either.
String indexedNoteTitle(String title, String? aliases) {
  final a = aliases?.trim() ?? '';
  return a.isEmpty ? title : '$title$_aliasSeparator$a';
}

/// What a result row shows for an indexed title (`⟦…⟧` marks kept): the
/// title alone, unless the match is in the aliases, which are then shown
/// after it.
String displayIndexedTitle(String marked) {
  final at = marked.indexOf(_aliasSeparator);
  if (at < 0) return marked;
  final aliases = marked.substring(at + 1);
  if (!aliases.contains(_open)) return marked.substring(0, at);
  return '${marked.substring(0, at)} · $aliases';
}

final searchIndexProvider = Provider<SearchIndex>((ref) {
  final index = SearchIndex(ref.watch(databaseProvider));
  ref.onDispose(index.dispose);
  return index;
});

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
