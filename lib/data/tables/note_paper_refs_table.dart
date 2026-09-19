import 'package:drift/drift.dart';

import 'notes_table.dart';
import 'papers_table.dart';

/// Join table linking a note to a paper it references, so the Library tab
/// can auto-aggregate every paper referenced across notes.
class NotePaperRefs extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {noteId, paperId};
}
