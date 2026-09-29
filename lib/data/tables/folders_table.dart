import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A single-parent grouping for notes, e.g. by project. A note belongs to
/// at most one folder (see Notes.folderId); folders themselves are flat,
/// no nesting, to keep the picker UI simple.
class Folders extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
