import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../ocr/ocr_service.dart' show pageLacksTextLayer;
import '../ocr/pdf_pages.dart';
import 'search_index.dart';

/// Identifies a PDF file's content cheaply (path, size, modified time); a
/// different stamp means the paper must be indexed again. Null: no file.
typedef PdfStamper = Future<String?> Function(String path);

Future<String?> fileStamp(String path) async {
  try {
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
  } catch (_) {
    return null;
  }
}

/// Full text of every PDF, per page, in a local FTS5 table beside
/// `search_index`. Derived: built on this device from the PDF text layer
/// (OCR text for scanned pages), never synced or backed up, rebuilt when
/// missing. Indexing runs in the background one paper and one page at a
/// time, yielding between pages, and resumes where it stopped.
class PdfTextIndex {
  PdfTextIndex(
    this._db,
    this._open, {
    PdfStamper stamper = fileStamp,
    this.maxPerPaper = 3,
  }) : _stamp = stamper;

  final AppDatabase _db;
  final PdfPagesOpener _open;
  final PdfStamper _stamp;

  /// Most matching pages shown for one paper.
  final int maxPerPaper;

  bool? _available;
  bool _disposed = false;
  Future<void>? _running;

  Future<bool> get available async {
    if (_available != null) return _available!;
    try {
      await _db.customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS pdf_pages_index USING fts5('
        'paper_id UNINDEXED, page UNINDEXED, text, '
        "tokenize = 'unicode61 remove_diacritics 2')",
      );
      await _db.customStatement(
        'CREATE TABLE IF NOT EXISTS pdf_index_state ('
        'paper_id TEXT PRIMARY KEY, stamp TEXT NOT NULL, '
        'page_count INTEGER NOT NULL, done_pages INTEGER NOT NULL)',
      );
      return _available = true;
    } catch (_) {
      return _available = false;
    }
  }

  void dispose() => _disposed = true;

  /// Starts (or joins) a background indexing pass; completes when every
  /// paper that can be indexed now has been. Never throws.
  Future<void> run() => _running ??= _runGuarded().whenComplete(() {
    _running = null;
  });

  /// Fire and forget.
  void kick() => unawaited(run());

  Future<void> _runGuarded() async {
    try {
      if (!await available) return;
      await _pass();
    } catch (_) {
      // The database may have closed mid-pass (app exit, tests).
    }
  }

  Future<void> _pass() async {
    await _db.customStatement(
      'DELETE FROM pdf_pages_index WHERE paper_id NOT IN '
      '(SELECT id FROM papers WHERE pdf_path IS NOT NULL)',
    );
    await _db.customStatement(
      'DELETE FROM pdf_index_state WHERE paper_id NOT IN '
      '(SELECT id FROM papers WHERE pdf_path IS NOT NULL)',
    );
    final papers = await (_db.select(
      _db.papers,
    )..where((p) => p.pdfPath.isNotNull())).get();
    for (final paper in papers) {
      if (_disposed) return;
      await _indexPaper(paper.id, paper.pdfPath!);
    }
  }

  Future<void> _indexPaper(String id, String path) async {
    final stamp = await _stamp(path);
    if (stamp == null) return;
    final state = await _db
        .customSelect(
          'SELECT stamp, page_count, done_pages FROM pdf_index_state '
          'WHERE paper_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    var done = 0;
    int? pageCount;
    if (state != null && state.read<String>('stamp') == stamp) {
      done = state.read<int>('done_pages');
      pageCount = state.read<int>('page_count');
      if (done >= pageCount) return;
    } else {
      await _forget(id);
    }

    PdfPages? pages;
    try {
      pages = await _open(path);
      final count = pages.pageCount;
      if (pageCount != count) {
        done = 0;
        await _forget(id);
      }
      await _db.customStatement(
        'INSERT OR REPLACE INTO pdf_index_state '
        '(paper_id, stamp, page_count, done_pages) VALUES (?, ?, ?, ?)',
        [id, stamp, count, done],
      );
      for (var i = done; i < count; i++) {
        if (_disposed) return;
        var text = await pages.text(i);
        if (pageLacksTextLayer(text)) {
          final ocr = await _ocrText(id, i + 1);
          if (ocr == null) {
            // A scan whose page isn't recognised yet: wait for OCR rather
            // than recording the page as empty.
            if (await _ocrPending(id)) return;
          } else {
            text = ocr;
          }
        }
        if (text.trim().isNotEmpty) {
          await _db.customStatement(
            'INSERT INTO pdf_pages_index (paper_id, page, text) '
            'VALUES (?, ?, ?)',
            [id, i + 1, text],
          );
        }
        await _db.customStatement(
          'UPDATE pdf_index_state SET done_pages = ? WHERE paper_id = ?',
          [i + 1, id],
        );
        // Give the UI thread a turn between pages.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    } catch (_) {
      // Unreadable or vanished PDF: try again on the next pass.
    } finally {
      try {
        await pages?.dispose();
      } catch (_) {}
    }
  }

  Future<String?> _ocrText(String paperId, int page) async {
    final row =
        await (_db.select(_db.ocrPages)..where(
              (o) => o.paperId.equals(paperId) & o.pageNumber.equals(page),
            ))
            .getSingleOrNull();
    final text = row?.content;
    return text == null || text.trim().isEmpty ? null : text;
  }

  /// A scanned paper still being recognised (an unrecognised page may
  /// still get text).
  Future<bool> _ocrPending(String paperId) async {
    final row = await (_db.select(
      _db.ocrPapers,
    )..where((o) => o.paperId.equals(paperId))).getSingleOrNull();
    return row != null && row.donePages < row.pageCount;
  }

  Future<void> _forget(String id) async {
    await _db.customStatement(
      'DELETE FROM pdf_pages_index WHERE paper_id = ?',
      [id],
    );
    await _db.customStatement(
      'DELETE FROM pdf_index_state WHERE paper_id = ?',
      [id],
    );
  }

  /// Whether some paper's text isn't fully indexed yet, so results may be
  /// incomplete.
  Future<bool> get incomplete async {
    if (!await available) return false;
    final row = await _db.customSelect('''
      SELECT 1 FROM papers p
      LEFT JOIN pdf_index_state s ON s.paper_id = p.id
      WHERE p.pdf_path IS NOT NULL
        AND (s.paper_id IS NULL OR s.done_pages < s.page_count)
      LIMIT 1''').getSingleOrNull();
    return row != null;
  }

  /// Pages whose text matches [query] (prefix matching, all words), best
  /// first, grouped by paper in order of each paper's best page, at most
  /// [maxPerPaper] per paper and [limit] in all. Snippets mark matches with
  /// `⟦…⟧` (see [splitMarked]).
  Future<List<SearchHit>> search(String query, {int limit = 30}) async {
    final terms = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).allMatches(query.toLowerCase()).map((m) => m.group(0)!).toList();
    if (terms.isEmpty || !await available) return const [];
    final match = terms.map((t) => '"$t"*').join(' ');
    final rows = await _db
        .customSelect(
          'SELECT x.paper_id, x.page, p.title, '
          "snippet(pdf_pages_index, 2, '⟦', '⟧', '…', 16) AS snip, "
          'bm25(pdf_pages_index) AS rank '
          'FROM pdf_pages_index x JOIN papers p ON p.id = x.paper_id '
          'WHERE pdf_pages_index MATCH ? ORDER BY rank LIMIT ?',
          variables: [Variable.withString(match), Variable.withInt(limit * 10)],
        )
        .get();
    final byPaper = <String, List<SearchHit>>{};
    for (final r in rows) {
      final id = r.read<String>('paper_id');
      final list = byPaper.putIfAbsent(id, () => []);
      if (list.length >= maxPerPaper) continue;
      list.add(
        SearchHit(
          kind: SearchKind.pdfText,
          id: id,
          title: r.read<String>('title'),
          snippet: r.read<String>('snip').replaceAll(RegExp(r'\s+'), ' '),
          paperId: id,
          page: r.read<int>('page'),
        ),
      );
    }
    return [for (final l in byPaper.values) ...l].take(limit).toList();
  }
}

final pdfTextIndexProvider = Provider<PdfTextIndex>((ref) {
  final index = PdfTextIndex(
    ref.watch(databaseProvider),
    ref.watch(pdfPagesOpenerProvider),
  );
  ref.onDispose(index.dispose);
  return index;
});

/// Read once at launch (e.g. from `HomeShell`): indexes papers' text in the
/// background and resumes unfinished work. Does nothing with no PDFs.
final pdfIndexStartupProvider = Provider<void>((ref) {
  ref.read(pdfTextIndexProvider).kick();
});
