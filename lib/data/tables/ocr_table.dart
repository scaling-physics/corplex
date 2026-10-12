import 'package:drift/drift.dart';

import 'papers_table.dart';

/// Text recognised (OCR) from a scanned PDF page. Derived data, local to
/// this device and deliberately *not* synced or backed up: each device
/// rebuilds it from the PDF.
class OcrPages extends Table {
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();

  /// 1-based, like `Highlights.pageNumber`.
  IntColumn get pageNumber => integer()();

  /// The page's recognised text, lines joined by newlines. Empty for a
  /// page with nothing to read (it is still recorded as done).
  TextColumn get content => text().withDefault(const Constant(''))();

  /// Lines and words with boxes as fractions (0..1) of the page; see
  /// `OcrPageText` in `lib/features/ocr/ocr_engine.dart`.
  TextColumn get wordsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {paperId, pageNumber};
}

/// A paper found to be scanned (no text layer), and how far recognising it
/// has got. Local-only, like [OcrPages].
class OcrPapers extends Table {
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageCount => integer()();

  /// Pages handled in order from the first (recognised, or skipped because
  /// they have a text layer). Done when it reaches [pageCount].
  IntColumn get donePages => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {paperId};
}
