import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/trash_table.dart';
import 'package:corplex/data/trash.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db.into(db.folders).insert(FoldersCompanion.insert(id: const Value('f1'), name: 'Research'));
    await db.into(db.tags).insert(TagsCompanion.insert(id: const Value('t1'), name: 'ml'));
    await db.into(db.papers).insert(PapersCompanion.insert(id: const Value('p1'), title: 'Attention'));
    await db.into(db.projects).insert(ProjectsCompanion.insert(id: const Value('pr1'), name: 'Thesis'));
    await db.into(db.notes).insert(NotesCompanion.insert(
      id: const Value('n1'),
      title: const Value('Lecture'),
      content: const Value('[{"insert":"important\\n"}]'),
      folderId: const Value('f1'),
      updatedAt: Value(DateTime.utc(2020)),
    ));
    await db.into(db.noteTags).insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1'));
    await db.into(db.notePaperRefs).insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
    await db.into(db.projectNotes).insert(ProjectNotesCompanion.insert(projectId: 'pr1', noteId: 'n1'));
    await db.into(db.attachments).insert(AttachmentsCompanion.insert(
      id: const Value('at1'),
      noteId: const Value('n1'),
      type: AttachmentType.podcast,
      path: const Value('/tmp/does-not-matter.m4a'),
      title: const Value('Overview'),
    ));
  });
  tearDown(() => db.close());

  test('trashing a note removes it and keeps a snapshot; restoring brings back everything', () async {
    final trashId = await trashNote(db, 'n1');

    expect(await db.select(db.notes).get(), isEmpty);
    expect(await db.select(db.attachments).get(), isEmpty);
    final item = await db.select(db.trashItems).getSingle();
    expect(item.title, 'Lecture');
    expect(item.kind, TrashKind.note);
    // Things the note pointed at are untouched.
    expect(await db.select(db.papers).get(), hasLength(1));
    expect(await db.select(db.tags).get(), hasLength(1));

    await restoreFromTrash(db, trashId);

    final note = await db.select(db.notes).getSingle();
    expect(note.title, 'Lecture');
    expect(note.content, contains('important'));
    expect(note.folderId, 'f1');
    expect((await db.select(db.attachments).getSingle()).title, 'Overview');
    expect(await db.select(db.noteTags).get(), hasLength(1));
    expect(await db.select(db.notePaperRefs).get(), hasLength(1));
    expect(await db.select(db.projectNotes).get(), hasLength(1));
    expect(await db.select(db.trashItems).get(), isEmpty);
  });

  test('a restored note is stamped now, so the restore wins the sync', () async {
    final trashId = await trashNote(db, 'n1');
    await restoreFromTrash(db, trashId);
    final note = await db.select(db.notes).getSingle();
    expect(note.updatedAt.isAfter(DateTime.utc(2024)), isTrue);
    // And it is queued for upload.
    final dirty = await db.customSelect(
      "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'notes'",
    ).getSingle();
    expect(dirty.read<int>('c'), 1);
  });

  test('restoring drops links to things deleted in the meantime', () async {
    final trashId = await trashNote(db, 'n1');
    await (db.delete(db.folders)..where((f) => f.id.equals('f1'))).go();
    await (db.delete(db.tags)..where((t) => t.id.equals('t1'))).go();
    await (db.delete(db.papers)..where((p) => p.id.equals('p1'))).go();

    await restoreFromTrash(db, trashId);

    final note = await db.select(db.notes).getSingle();
    expect(note.folderId, isNull, reason: 'the folder is gone');
    expect(await db.select(db.noteTags).get(), isEmpty);
    expect(await db.select(db.notePaperRefs).get(), isEmpty);
    expect(await db.select(db.projectNotes).get(), hasLength(1), reason: 'that project still exists');
  });

  test('trashing a paper keeps its highlights, ink, note links and projects', () async {
    await db.into(db.highlights).insert(HighlightsCompanion.insert(
      id: const Value('h1'), paperId: 'p1', pageNumber: 2, quote: 'q', rectsJson: '[]',
    ));
    await db.into(db.annotations).insert(AnnotationsCompanion.insert(
      id: const Value('a1'), paperId: 'p1', pageNumber: 1, pointsJson: '[]',
    ));
    await db.into(db.projectPapers).insert(ProjectPapersCompanion.insert(projectId: 'pr1', paperId: 'p1'));

    final trashId = await trashPaper(db, 'p1');
    expect(await db.select(db.papers).get(), isEmpty);
    expect(await db.select(db.highlights).get(), isEmpty);
    expect(await db.select(db.notePaperRefs).get(), isEmpty);

    await restoreFromTrash(db, trashId);

    expect((await db.select(db.papers).getSingle()).title, 'Attention');
    expect(await db.select(db.highlights).get(), hasLength(1));
    expect(await db.select(db.annotations).get(), hasLength(1));
    expect(await db.select(db.notePaperRefs).get(), hasLength(1));
    expect(await db.select(db.projectPapers).get(), hasLength(1));
  });

  group('purging', () {
    test('only entries past the retention period go, with their files', () async {
      final tmp = Directory.systemTemp.createTempSync('trash');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final oldFile = File('${tmp.path}/old.m4a')..writeAsBytesSync([1]);
      final freshFile = File('${tmp.path}/fresh.m4a')..writeAsBytesSync([1]);
      await db.into(db.attachments).insert(AttachmentsCompanion.insert(
        id: const Value('old'), noteId: const Value('n1'), type: AttachmentType.podcast, path: Value(oldFile.path),
      ));
      await trashNote(db, 'n1'); // includes the old attachment
      await (db.update(db.trashItems)).write(
        TrashItemsCompanion(deletedAt: Value(DateTime.now().subtract(const Duration(days: 45)))),
      );

      await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('n2'), title: const Value('Recent')));
      await db.into(db.attachments).insert(AttachmentsCompanion.insert(
        id: const Value('fresh'), noteId: const Value('n2'), type: AttachmentType.podcast, path: Value(freshFile.path),
      ));
      await trashNote(db, 'n2');

      final purged = await purgeTrash(db);

      expect(purged, 1);
      expect((await db.select(db.trashItems).getSingle()).title, 'Recent');
      expect(oldFile.existsSync(), isFalse);
      expect(freshFile.existsSync(), isTrue);
    });

    test('a file still used elsewhere is kept', () async {
      final tmp = Directory.systemTemp.createTempSync('trash');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final shared = File('${tmp.path}/shared.pdf')..writeAsBytesSync([1]);
      await db.into(db.papers).insert(PapersCompanion.insert(
        id: const Value('pa'), title: 'A', pdfPath: Value(shared.path),
      ));
      await db.into(db.papers).insert(PapersCompanion.insert(
        id: const Value('pb'), title: 'B', pdfPath: Value(shared.path),
      ));
      await trashPaper(db, 'pa');

      await purgeTrash(db, all: true);

      expect(shared.existsSync(), isTrue, reason: 'paper B still points at it');
      expect(await db.select(db.trashItems).get(), isEmpty);
    });

    test('emptying the trash purges everything', () async {
      await trashNote(db, 'n1');
      await trashPaper(db, 'p1');
      expect(await purgeTrash(db, all: true), 2);
      expect(await db.select(db.trashItems).get(), isEmpty);
    });
  });
}
