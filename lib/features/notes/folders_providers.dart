import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final foldersListProvider = StreamProvider.autoDispose<List<Folder>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.folders,
  )..orderBy([(f) => OrderingTerm.asc(f.name)])).watch();
});

Future<String> createFolder(AppDatabase db, String name) async {
  final id = const Uuid().v4();
  await db
      .into(db.folders)
      .insert(FoldersCompanion.insert(id: Value(id), name: name));
  return id;
}

Future<void> setNoteFolder(
  AppDatabase db, {
  required String noteId,
  required String? folderId,
}) {
  return (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
    NotesCompanion(folderId: Value(folderId)),
  );
}

Future<void> deleteFolder(AppDatabase db, String folderId) {
  return (db.delete(db.folders)..where((f) => f.id.equals(folderId))).go();
}
