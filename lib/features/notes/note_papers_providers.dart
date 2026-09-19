import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// Every paper linked to this note, via NotePaperRefs.
final linkedPapersForNoteProvider = StreamProvider.autoDispose
    .family<List<Paper>, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.papers).join([
              innerJoin(
                db.notePaperRefs,
                db.notePaperRefs.paperId.equalsExp(db.papers.id),
              ),
            ])
            ..where(db.notePaperRefs.noteId.equals(noteId));
      return query.watch().map(
        (rows) => rows.map((row) => row.readTable(db.papers)).toList(),
      );
    });

Future<void> linkPaperToNote(
  AppDatabase db, {
  required String noteId,
  required String paperId,
}) {
  return db
      .into(db.notePaperRefs)
      .insert(
        NotePaperRefsCompanion.insert(noteId: noteId, paperId: paperId),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> unlinkPaperFromNote(
  AppDatabase db, {
  required String noteId,
  required String paperId,
}) {
  return (db.delete(db.notePaperRefs)..where(
        (t) => t.noteId.equals(noteId) & t.paperId.equals(paperId),
      ))
      .go();
}
