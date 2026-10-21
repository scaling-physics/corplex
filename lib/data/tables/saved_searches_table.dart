import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// A search the user kept, run again with one tap (schema v22, synced).
/// [query] is the text as typed, operators included (`tag:`, `"…"`, …).
class SavedSearches extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  TextColumn get query => text()();

  /// Order in the list; null until the user reorders (then by creation).
  IntColumn get position => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
