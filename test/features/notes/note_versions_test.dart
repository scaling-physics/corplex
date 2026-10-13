import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/sync_schema.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/notes/note_versions.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

String body(List<String> lines) => jsonEncode([
  {'insert': '${lines.join('\n')}\n'},
]);

void main() {
  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Ch 1'),
            content: Value(body(['one', 'two', 'three'])),
          ),
        );
  });
  tearDown(() => db.close());

  Future<List<NoteVersion>> versions() => (db.select(
    db.noteVersions,
  )..orderBy([(v) => OrderingTerm.desc(v.createdAt)])).get();

  test('sync spec lists note_versions after notes', () {
    final names = [for (final t in syncTables) t.name];
    expect(names.indexOf('note_versions'), greaterThan(names.indexOf('notes')));
  });

  group('diffLines', () {
    List<String> run(List<String> a, List<String> b) => [
      for (final l in diffLines(a, b)) l.toString(),
    ];

    test('identical', () {
      expect(run(['a', 'b'], ['a', 'b']), [' a', ' b']);
    });
    test('added, removed and changed lines', () {
      expect(run(['a', 'b', 'c'], ['a', 'c', 'd']), [' a', '-b', ' c', '+d']);
      expect(run(['a', 'b'], ['a', 'x']), [' a', '-b', '+x']);
      expect(run([], ['a']), ['+a']);
      expect(run(['a'], []), ['-a']);
    });
    test('moved text shows as removed then added', () {
      expect(run(['a', 'b', 'c'], ['b', 'c', 'a']), ['-a', ' b', ' c', '+a']);
    });
  });

  test(
    'saveNoteVersion snapshots title and body; empty label is null',
    () async {
      await saveNoteVersion(db, 'n', label: '  ');
      await saveNoteVersion(db, 'n', label: 'Draft 1');
      final all = await versions();
      expect(all, hasLength(2));
      expect(all.map((v) => v.label), containsAll([null, 'Draft 1']));
      expect(all.first.title, 'Ch 1');
      expect(all.first.content, body(['one', 'two', 'three']));
    },
  );

  test('moving to With supervisor saves one version, once', () async {
    final pr = await findOrCreateProject(db, 'Thesis');
    await addNoteToProject(db, projectId: pr, noteId: 'n');
    await setChapterStatus(db, pr, 'n', ChapterStatus.draft);
    expect(await versions(), isEmpty);

    await setChapterStatus(db, pr, 'n', ChapterStatus.withSupervisor);
    expect((await versions()).single.label, sentToSupervisorLabel);

    // Same status again: nothing new.
    await setChapterStatus(db, pr, 'n', ChapterStatus.withSupervisor);
    expect(await versions(), hasLength(1));

    // Back and forth with identical content: deduped.
    await setChapterStatus(db, pr, 'n', ChapterStatus.revised);
    await setChapterStatus(db, pr, 'n', ChapterStatus.withSupervisor);
    expect(await versions(), hasLength(1));

    // Edited meanwhile: a new version.
    await (db.update(db.notes)..where((n) => n.id.equals('n'))).write(
      NotesCompanion(content: Value(body(['one', 'changed']))),
    );
    await setChapterStatus(db, pr, 'n', ChapterStatus.revised);
    await setChapterStatus(db, pr, 'n', ChapterStatus.withSupervisor);
    expect(await versions(), hasLength(2));
  });

  test(
    'restore replaces the note and keeps the current text as a version',
    () async {
      await saveNoteVersion(db, 'n', label: 'Old');
      final old = (await versions()).single;
      await (db.update(db.notes)..where((n) => n.id.equals('n'))).write(
        NotesCompanion(
          title: const Value('Renamed'),
          content: Value(body(['brand new'])),
        ),
      );

      expect(await restoreNoteVersion(db, old.id), isTrue);
      final note = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('n'))).getSingle();
      expect(note.title, 'Ch 1');
      expect(note.content, body(['one', 'two', 'three']));

      final all = await versions();
      expect(all, hasLength(2));
      final safety = all.firstWhere((v) => v.label == beforeRestoringLabel);
      expect(safety.title, 'Renamed');
      expect(safety.content, body(['brand new']));
    },
  );

  test('rename, delete and undo', () async {
    await saveNoteVersion(db, 'n');
    final v = (await versions()).single;
    await setVersionLabel(db, v.id, 'Named');
    expect((await versions()).single.label, 'Named');
    final row = await deleteNoteVersion(db, v.id);
    expect(await versions(), isEmpty);
    await undoDeleteNoteVersion(db, row!);
    expect((await versions()).single.label, 'Named');
  });

  test(
    'trash snapshot carries versions and restore brings them back',
    () async {
      await saveNoteVersion(db, 'n', label: 'Keep me');
      final trashId = await trashNote(db, 'n');
      expect(await versions(), isEmpty, reason: 'cascade removed them');

      await restoreFromTrash(db, trashId);
      final back = await versions();
      expect(back.single.label, 'Keep me');
      expect(back.single.noteId, 'n');
    },
  );
}
