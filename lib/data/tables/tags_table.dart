import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A free-form label a note can carry any number of, added any time —
/// unlike a folder, tagging is never required to capture a note.
class Tags extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
