import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'notes_table.dart';

/// A comment on a passage of a note — typically a supervisor's feedback on
/// a chapter, typed in by the writer — schema v19, synced. It is anchored
/// to the passage by its text ([quote]) and where it was ([anchor], in the
/// editor document), so it can be found again after edits. Marked
/// [resolved] once addressed. Deleting the note deletes its comments.
class NoteComments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// The commented passage as it read when the comment was made.
  TextColumn get quote => text().withDefault(const Constant(''))();

  /// Where the passage started (editor-document offset); a hint for finding
  /// [quote] again, which wins when they disagree.
  IntColumn get anchor => integer().withDefault(const Constant(0))();

  /// The comment itself.
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Who made it, if the writer noted that ("Supervisor", a name).
  TextColumn get author => text().nullable()();

  /// Addressed. Synced as an integer 0/1 (see Notes.pinned).
  BoolColumn get resolved => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
