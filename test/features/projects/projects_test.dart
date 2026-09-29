import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/projects/projects_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
        );
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p2'), title: 'BERT'));
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Lecture'),
          ),
        );
  });
  tearDown(() => db.close());

  test('findOrCreateProject reuses a name, ignoring case and spaces', () async {
    final a = await findOrCreateProject(db, 'Thesis ch. 2');
    final b = await findOrCreateProject(db, '  thesis CH. 2 ');
    expect(b, a);
    expect(await db.select(db.projects).get(), hasLength(1));
    expect((await db.select(db.projects).getSingle()).name, 'Thesis ch. 2');
  });

  test(
    'papers and notes can be in several projects, and added twice safely',
    () async {
      final review = await findOrCreateProject(db, 'Review');
      final thesis = await findOrCreateProject(db, 'Thesis');

      await addPaperToProject(db, projectId: review, paperId: 'p1');
      await addPaperToProject(db, projectId: review, paperId: 'p1');
      await addPaperToProject(db, projectId: thesis, paperId: 'p1');
      await addPaperToProject(db, projectId: review, paperId: 'p2');
      await addNoteToProject(db, projectId: review, noteId: 'n1');

      expect(await db.select(db.projectPapers).get(), hasLength(3));
      expect(await db.select(db.projectNotes).get(), hasLength(1));

      await removePaperFromProject(db, projectId: review, paperId: 'p1');
      expect(await db.select(db.projectPapers).get(), hasLength(2));
    },
  );

  test('deleting a project keeps its papers and notes', () async {
    final id = await findOrCreateProject(db, 'Review');
    await addPaperToProject(db, projectId: id, paperId: 'p1');
    await addNoteToProject(db, projectId: id, noteId: 'n1');

    await deleteProject(db, id);

    expect(await db.select(db.projects).get(), isEmpty);
    expect(await db.select(db.projectPapers).get(), isEmpty);
    expect(await db.select(db.projectNotes).get(), isEmpty);
    expect(await db.select(db.papers).get(), hasLength(2));
    expect(await db.select(db.notes).get(), hasLength(1));
  });

  test('deleting a paper or note removes it from its projects only', () async {
    final id = await findOrCreateProject(db, 'Review');
    await addPaperToProject(db, projectId: id, paperId: 'p1');
    await addNoteToProject(db, projectId: id, noteId: 'n1');

    await (db.delete(db.papers)..where((p) => p.id.equals('p1'))).go();
    await (db.delete(db.notes)..where((n) => n.id.equals('n1'))).go();

    expect(await db.select(db.projectPapers).get(), isEmpty);
    expect(await db.select(db.projectNotes).get(), isEmpty);
    expect(await db.select(db.projects).get(), hasLength(1));
  });

  test('rename', () async {
    final id = await findOrCreateProject(db, 'Old');
    await renameProject(db, id, '  New name ');
    expect((await db.select(db.projects).getSingle()).name, 'New name');
  });
}
