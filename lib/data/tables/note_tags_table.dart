import 'package:drift/drift.dart';

import 'notes_table.dart';
import 'tags_table.dart';

/// Join table linking a note to each tag it carries.
class NoteTags extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
