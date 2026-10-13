import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'notes_table.dart';

/// A saved copy of a note (a chapter sent to a supervisor, a draft worth
/// keeping), schema v16. Synced, so versions show on every device.
/// Immutable once written, except [label]; deleting the note deletes its
/// versions.
class NoteVersions extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// The note's title and body (Quill Delta JSON, as stored) at that time.
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// "Sent to supervisor", a name the reader typed, or null.
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
