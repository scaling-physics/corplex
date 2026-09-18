import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('insert a note and read it back', () async {
    final id = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(title: const Value('First note')));

    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();

    expect(note.title, 'First note');
  });

  test('a paper can be referenced by a note and found via the join table', () async {
    final noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(title: const Value('Reading notes')));
    final paperId = await db
        .into(db.papers)
        .insert(PapersCompanion.insert(title: 'Attention Is All You Need'));

    await db
        .into(db.notePaperRefs)
        .insert(NotePaperRefsCompanion.insert(noteId: noteId, paperId: paperId));

    final refs = await db.select(db.notePaperRefs).get();
    expect(refs, hasLength(1));
    expect(refs.single.paperId, paperId);
  });

  test('an attachment can be linked to a paper', () async {
    final paperId = await db
        .into(db.papers)
        .insert(PapersCompanion.insert(title: 'Some Paper'));

    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            paperId: Value(paperId),
            type: AttachmentType.podcast,
            url: const Value('https://notebooklm.google.com/notebook/abc'),
          ),
        );

    final attachments = await db.select(db.attachments).get();
    expect(attachments.single.type, AttachmentType.podcast);
  });
}
