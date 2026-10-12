import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'ocr_engine.dart';
import 'pdf_pages.dart';

/// A page "lacks a text layer" when it has next to no letters or digits.
/// Stray page numbers or watermarks on a scan don't count as text.
bool pageLacksTextLayer(String text, {int minChars = 25}) {
  var n = 0;
  for (final r in text.runes) {
    final isAlnum =
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x41 && r <= 0x5a) ||
        (r >= 0x61 && r <= 0x7a) ||
        r > 0xbf;
    if (isAlnum && ++n >= minChars) return false;
  }
  return true;
}

/// How far a scanned paper's recognition has got.
class OcrProgress {
  const OcrProgress(this.pageCount, this.donePages);

  final int pageCount;
  final int donePages;

  bool get isDone => donePages >= pageCount;
  double get fraction => pageCount == 0 ? 1 : donePages / pageCount;
}

/// Recognises scanned PDF pages on-device and stores the text. One page at
/// a time, in the background, never blocking the UI.
class OcrService {
  OcrService(this._db, this._engine, this._open);

  final AppDatabase _db;
  final OcrEngine _engine;
  final PdfPagesOpener _open;

  final List<String> _queue = [];
  final Set<String> _cancelled = {};
  Completer<void>? _idle;
  bool _running = false;
  bool _disposed = false;

  /// Papers waiting or in progress, in order.
  List<String> get queued => List.unmodifiable(_queue);

  /// Marks [paperId] as a scanned paper of [pageCount] pages (idempotent;
  /// keeps progress already made).
  Future<void> markScanned(String paperId, int pageCount) async {
    final existing = await (_db.select(
      _db.ocrPapers,
    )..where((o) => o.paperId.equals(paperId))).getSingleOrNull();
    if (existing != null) {
      if (existing.pageCount != pageCount) {
        await (_db.update(_db.ocrPapers)
              ..where((o) => o.paperId.equals(paperId)))
            .write(OcrPapersCompanion(pageCount: Value(pageCount)));
      }
      return;
    }
    await _db
        .into(_db.ocrPapers)
        .insert(
          OcrPapersCompanion.insert(paperId: paperId, pageCount: pageCount),
        );
  }

  /// Recognises page [index] (0-based) of an open document and stores it,
  /// unless it has a text layer (returns null then) or was done already
  /// (returns the stored text). Returns the page's recognised text.
  Future<OcrPageText?> recognizePage(
    PdfPages pages,
    String paperId,
    int index, {
    bool force = false,
  }) async {
    final existing = await storedPage(paperId, index + 1);
    if (existing != null && !force) return existing;
    if (!pageLacksTextLayer(await pages.text(index))) return null;
    final png = await pages.renderPng(index);
    if (png == null) return null;
    final result = await _engine.recognize(png);
    await _db
        .into(_db.ocrPages)
        .insertOnConflictUpdate(
          OcrPagesCompanion.insert(
            paperId: paperId,
            pageNumber: index + 1,
            content: Value(result.text),
            wordsJson: Value(result.toJsonString()),
          ),
        );
    return result;
  }

  Future<OcrPageText?> storedPage(String paperId, int pageNumber) async {
    final row =
        await (_db.select(_db.ocrPages)..where(
              (o) =>
                  o.paperId.equals(paperId) & o.pageNumber.equals(pageNumber),
            ))
            .getSingleOrNull();
    return row == null ? null : OcrPageText.fromJsonString(row.wordsJson);
  }

  /// Puts [paperId] on the background queue (its PDF path is read from the
  /// paper). Starts working if idle. No-op for papers not marked scanned.
  void enqueue(String paperId) {
    _cancelled.remove(paperId);
    if (_queue.contains(paperId) || _disposed) return;
    _queue.add(paperId);
    if (!_running) unawaited(_run());
  }

  /// Stops work on [paperId] after the page in progress.
  void cancel(String paperId) {
    _queue.remove(paperId);
    _cancelled.add(paperId);
  }

  void cancelAll() {
    _cancelled.addAll(_queue);
    _queue.clear();
  }

  /// Queues every scanned paper that isn't finished (call once at launch).
  Future<void> resumePending() async {
    final rows = await _db.select(_db.ocrPapers).get();
    for (final r in rows) {
      if (r.donePages < r.pageCount) enqueue(r.paperId);
    }
  }

  /// Completes when the queue has drained (for tests and shutdown).
  Future<void> whenIdle() => _idle?.future ?? Future.value();

  void dispose() {
    _disposed = true;
    cancelAll();
  }

  Future<void> _run() async {
    _running = true;
    _idle = Completer<void>();
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final id = _queue.first;
        try {
          await _work(id);
        } catch (_) {
          // Unreadable PDF or an engine failure: skip this paper for now;
          // it stays unfinished and is retried next launch.
        }
        _queue.remove(id);
        _cancelled.remove(id);
      }
    } finally {
      _running = false;
      _idle?.complete();
    }
  }

  bool _stop(String id) => _disposed || _cancelled.contains(id);

  Future<void> _work(String paperId) async {
    final paper = await (_db.select(
      _db.papers,
    )..where((p) => p.id.equals(paperId))).getSingleOrNull();
    final job = await (_db.select(
      _db.ocrPapers,
    )..where((o) => o.paperId.equals(paperId))).getSingleOrNull();
    final path = paper?.pdfPath;
    if (paper == null || job == null || path == null) return;
    final pages = await _open(path);
    try {
      final count = pages.pageCount < job.pageCount
          ? pages.pageCount
          : job.pageCount;
      for (var i = job.donePages; i < count; i++) {
        if (_stop(paperId)) return;
        await recognizePage(pages, paperId, i);
        // The paper may have been deleted (cascade) while recognising.
        final n =
            await (_db.update(_db.ocrPapers)
                  ..where((o) => o.paperId.equals(paperId)))
                .write(OcrPapersCompanion(donePages: Value(i + 1)));
        if (n == 0) return;
      }
    } finally {
      await pages.dispose();
    }
  }
}

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService(
    ref.watch(databaseProvider),
    ref.watch(ocrEngineProvider),
    ref.watch(pdfPagesOpenerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Read once at launch (e.g. from `HomeShell`) to finish unfinished scans.
final ocrStartupProvider = FutureProvider<void>((ref) async {
  await ref.read(ocrServiceProvider).resumePending();
});

/// Recognised text for (paper, 1-based page); null when there is none.
final ocrPageTextProvider = StreamProvider.autoDispose
    .family<OcrPageText?, ({String paperId, int page})>((ref, key) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.ocrPages)..where(
            (o) =>
                o.paperId.equals(key.paperId) & o.pageNumber.equals(key.page),
          ))
          .watchSingleOrNull()
          .map(
            (r) => r == null ? null : OcrPageText.fromJsonString(r.wordsJson),
          );
    });

/// Progress for a scanned paper; null if the paper isn't scanned.
final ocrProgressProvider = StreamProvider.autoDispose
    .family<OcrProgress?, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.ocrPapers)..where((o) => o.paperId.equals(paperId)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : OcrProgress(r.pageCount, r.donePages));
    });

/// Whether the paper is a scan (has an OCR record).
final isScannedPaperProvider = Provider.autoDispose.family<bool, String>(
  (ref, paperId) => ref.watch(ocrProgressProvider(paperId)).value != null,
);
