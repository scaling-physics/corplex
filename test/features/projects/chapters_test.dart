import 'dart:async';
import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corplex/data/database_provider.dart';

void main() {
  late AppDatabase db;
  late String pr;

  String body(int words) => jsonEncode([
    {'insert': '${List.filled(words, 'word').join(' ')}\n'},
  ]);

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    pr = await findOrCreateProject(db, 'Thesis');
    for (final (id, day, words) in [('a', 1, 10), ('b', 2, 20), ('c', 3, 30)]) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value('Ch $id'),
              content: Value(body(words)),
              createdAt: Value(DateTime(2026, 1, day)),
            ),
          );
      await addNoteToProject(db, projectId: pr, noteId: id);
    }
  });
  tearDown(() => db.close());

  Future<List<String>> order() async => [
    for (final n in await orderedProjectNotes(db, pr)) n.id,
  ];

  test('reorder persists positions; later additions go last', () async {
    expect(await order(), ['a', 'b', 'c']);
    await reorderChapters(db, pr, ['c', 'a', 'b']);
    expect(await order(), ['c', 'a', 'b']);
    await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('d')));
    await addNoteToProject(db, projectId: pr, noteId: 'd');
    expect(await order(), ['c', 'a', 'b', 'd']);
  });

  test('addChapter appends a new note even before any reorder', () async {
    await db
        .update(db.notes)
        .write(NotesCompanion(createdAt: Value(DateTime(2026, 6, 1))));
    final id = await addChapter(db, pr);
    expect((await order()).last, id);
    expect((await order()).length, 4);
  });

  test('status and target edits, with words and summary', () async {
    await setChapterStatus(db, pr, 'a', ChapterStatus.finished);
    await setChapterStatus(db, pr, 'b', ChapterStatus.draft);
    await setChapterTarget(db, pr, 'b', 40);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final done = Completer<List<Chapter>>();
    container.listen(projectChaptersProvider(pr), (_, v) {
      if (v.hasValue && !done.isCompleted) done.complete(v.value!);
    }, fireImmediately: true);
    final chapters = await done.future;
    expect([for (final c in chapters) c.words], [10, 20, 30]);
    expect(chapters[1].status, ChapterStatus.draft);
    expect(chapters[1].progress, 0.5);
    expect(chapters[0].progress, isNull);
    final s = ChapterSummary(chapters);
    expect(s.wordsLabel, '60 / 40 words');
    expect(s.finishedLabel, '1 of 3 chapters final');

    await setChapterStatus(db, pr, 'a', null);
    await setChapterTarget(db, pr, 'b', 0);
    final row = await (db.select(
      db.projectNotes,
    )..where((r) => r.noteId.equals('b'))).getSingle();
    expect(row.wordTarget, isNull);
  });

  test('due label counts days', () {
    final now = DateTime(2026, 10, 12, 15);
    expect(dueLabel(DateTime(2026, 10, 12), now), 'Due today · 12 October');
    expect(dueLabel(DateTime(2026, 10, 13), now), 'Due 13 October · 1 day');
    expect(
      dueLabel(DateTime(2027, 3, 14), now),
      'Due 14 March 2027 · 153 days',
    );
    expect(dueLabel(DateTime(2026, 10, 9), now), 'Due 9 October · 3 days ago');
  });

  test('due date set and cleared', () async {
    await setProjectDueDate(db, pr, DateTime(2027, 3, 14, 9));
    var p = await db.select(db.projects).getSingle();
    expect(p.dueDate, DateTime(2027, 3, 14));
    await setProjectDueDate(db, pr, null);
    p = await db.select(db.projects).getSingle();
    expect(p.dueDate, isNull);
  });
}
