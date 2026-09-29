import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A referenced paper/source, the unit the Library tab lists and searches.
/// Primary key is a client-generated UUID (see notes_table.dart for why).
class Papers extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get title => text()();
  TextColumn get authors => text().withDefault(const Constant(''))();
  IntColumn get year => integer().nullable()();
  TextColumn get venue => text().nullable()();
  TextColumn get doi => text().nullable()();

  /// Local file path to the imported PDF, if any.
  TextColumn get pdfPath => text().nullable()();

  /// Object key of the PDF in cloud storage once uploaded (synced, unlike
  /// [pdfPath], which only means something on this device).
  TextColumn get storageKey => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
