import 'package:drift/drift.dart';

import 'papers_table.dart';

/// A single freeform highlighter stroke drawn on one page of a paper's PDF.
/// [pointsJson] is a JSON-encoded list of `[x, y]` pairs normalized to the
/// 0..1 range relative to the page's rendered width/height, so a stroke
/// scales correctly regardless of zoom level or render resolution.
class Annotations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paperId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageNumber => integer()();
  TextColumn get colorHex => text().withDefault(const Constant('#FFEB3B'))();
  TextColumn get pointsJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
