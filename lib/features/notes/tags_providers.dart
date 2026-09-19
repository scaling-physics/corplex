import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final tagsListProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.tags,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
});

final tagsForNoteProvider = StreamProvider.autoDispose.family<List<Tag>, String>((
  ref,
  noteId,
) {
  final db = ref.watch(databaseProvider);
  final query =
      db.select(db.tags).join([
          innerJoin(db.noteTags, db.noteTags.tagId.equalsExp(db.tags.id)),
        ])
        ..where(db.noteTags.noteId.equals(noteId));
  return query.watch().map(
    (rows) => rows.map((row) => row.readTable(db.tags)).toList(),
  );
});

/// Finds an existing tag with this name (case-insensitive) or creates one.
Future<String> findOrCreateTag(AppDatabase db, String name) async {
  final trimmed = name.trim();
  final existing =
      await (db.select(db.tags)
            ..where((t) => t.name.lower().equals(trimmed.toLowerCase())))
          .getSingleOrNull();
  if (existing != null) return existing.id;

  final id = const Uuid().v4();
  await db
      .into(db.tags)
      .insert(TagsCompanion.insert(id: Value(id), name: trimmed));
  return id;
}

Future<void> addTagToNote(
  AppDatabase db, {
  required String noteId,
  required String tagId,
}) {
  return db
      .into(db.noteTags)
      .insert(
        NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> deleteTag(AppDatabase db, String tagId) {
  return (db.delete(db.tags)..where((t) => t.id.equals(tagId))).go();
}

Future<void> removeTagFromNote(
  AppDatabase db, {
  required String noteId,
  required String tagId,
}) {
  return (db.delete(db.noteTags)..where(
        (t) => t.noteId.equals(noteId) & t.tagId.equals(tagId),
      ))
      .go();
}
