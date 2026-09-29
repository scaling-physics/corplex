import 'package:drift/drift.dart';

import 'notes_table.dart';
import 'tags_table.dart';

/// Join table linking a note to each tag it carries.
class NoteTags extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  /// When the link was made; sync uses it for last-write-wins.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
