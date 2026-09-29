import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'papers_table.dart';

/// A passage of a paper's text the reader highlighted. Unlike freeform ink
/// ([Annotations]), it keeps the actual [text], so it can be quoted into a
/// note, searched and cited with its page number.
class Highlights extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageNumber => integer()();

  /// The highlighted passage, as extracted from the PDF's text layer.
  TextColumn get quote => text()();

  /// One box per line, as `[[left, top, right, bottom], …]` fractions of the
  /// page's width/height, so it lines up at any zoom level.
  TextColumn get rectsJson => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#f2d66b'))();

  /// The reader's own remark about the passage.
  TextColumn get comment => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
