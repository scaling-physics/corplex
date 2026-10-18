import 'package:flutter/foundation.dart' show mapEquals;
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

Future<void> renameFolder(AppDatabase db, String folderId, String name) =>
    (db.update(db.folders)..where((f) => f.id.equals(folderId))).write(
      FoldersCompanion(name: Value(name)),
    );

/// How many notes each folder holds (key null: notes in no folder), for the
/// Mac sidebar's counts. Live.
final folderNoteCountsProvider = StreamProvider.autoDispose<Map<String?, int>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT folder_id AS id, COUNT(*) AS n FROM notes GROUP BY folder_id',
        readsFrom: {db.notes},
      )
      .watch()
      .map(
        (rows) => {
          for (final r in rows) r.read<String?>('id'): r.read<int>('n'),
        },
      )
      // A save in an open note re-runs the counts; same counts, no rebuild.
      .distinct(mapEquals);
});
