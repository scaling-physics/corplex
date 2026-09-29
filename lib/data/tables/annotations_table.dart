import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'papers_table.dart';

/// A single freeform highlighter stroke drawn on one page of a paper's PDF.
/// [pointsJson] is a JSON-encoded list of `[x, y]` pairs normalized to the
/// 0..1 range relative to the page's rendered width/height, so a stroke
/// scales correctly regardless of zoom level or render resolution.
/// Primary key is a client-generated UUID (see notes_table.dart for why).
class Annotations extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageNumber => integer()();
  TextColumn get colorHex => text().withDefault(const Constant('#FFEB3B'))();
  TextColumn get pointsJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
