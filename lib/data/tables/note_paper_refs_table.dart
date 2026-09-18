import 'package:drift/drift.dart';

import 'notes_table.dart';
import 'papers_table.dart';

/// Join table linking a note to a paper it references, so the Library tab
/// can auto-aggregate every paper referenced across notes.
class NotePaperRefs extends Table {
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get paperId =>
      integer().references(Papers, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {noteId, paperId};
}
