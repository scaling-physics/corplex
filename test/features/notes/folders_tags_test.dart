import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/folders_providers.dart';
import 'package:corplex/features/notes/tags_providers.dart';

void main() {
  late AppDatabase db;
  late String noteId;

  setUp(() async {
    db = AppDatabase.inMemoryForTesting();
    noteId = const Uuid().v4();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(noteId),
            title: const Value('My note'),
          ),
        );
  });

  tearDown(() => db.close());

  group('folders', () {
    test('creating a folder and assigning it to a note', () async {
      final folderId = await createFolder(db, 'Research');
      await setNoteFolder(db, noteId: noteId, folderId: folderId);

      final note = await db.select(db.notes).getSingle();
      expect(note.folderId, folderId);
    });

    test(
      'deleting a folder unfiles its notes rather than deleting them',
      () async {
        final folderId = await createFolder(db, 'Research');
        await setNoteFolder(db, noteId: noteId, folderId: folderId);

        await deleteFolder(db, folderId);

        final note = await db.select(db.notes).getSingle();
        expect(note.folderId, isNull);
      },
    );
  });

  group('tags', () {
    test('findOrCreateTag reuses an existing tag case-insensitively', () async {
      final firstId = await findOrCreateTag(db, 'To-Cite');
      final secondId = await findOrCreateTag(db, 'to-cite');

      expect(secondId, firstId);
      final allTags = await db.select(db.tags).get();
      expect(allTags, hasLength(1));
    });

    test(
      'adding a tag twice does not duplicate the link (insertOrIgnore)',
      () async {
        final tagId = await findOrCreateTag(db, 'idea');
        await addTagToNote(db, noteId: noteId, tagId: tagId);
        await addTagToNote(db, noteId: noteId, tagId: tagId);

        final links = await db.select(db.noteTags).get();
        expect(links, hasLength(1));
      },
    );

    test('removing a tag from a note leaves the tag itself intact', () async {
      final tagId = await findOrCreateTag(db, 'idea');
      await addTagToNote(db, noteId: noteId, tagId: tagId);
      await removeTagFromNote(db, noteId: noteId, tagId: tagId);

      final links = await db.select(db.noteTags).get();
      expect(links, isEmpty);
      final tag = await db.select(db.tags).getSingle();
      expect(tag.name, 'idea');
    });

    test('deleting a tag removes it from every note', () async {
      final tagId = await findOrCreateTag(db, 'idea');
      await addTagToNote(db, noteId: noteId, tagId: tagId);

      await deleteTag(db, tagId);

      final links = await db.select(db.noteTags).get();
      expect(links, isEmpty);
      final tags = await db.select(db.tags).get();
      expect(tags, isEmpty);
    });
  });
}
