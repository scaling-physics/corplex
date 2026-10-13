import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/figures.dart';
import 'package:corplex/features/projects/projects_providers.dart';

String _c(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  late AppDatabase db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  Future<void> note(String id, String content) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(id),
          content: Value(content),
        ),
      );

  Future<String> project(String name, DateTime at) async {
    final id = await findOrCreateProject(db, name);
    await (db.update(db.projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(createdAt: Value(at)),
    );
    return id;
  }

  Future<void> expectNumber(
    String noteId,
    String label,
    String? chapter,
    String? name,
  ) async {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    final sub = c.listen(figureContextProvider(noteId), (_, _) {});
    // Let the two upstream streams deliver.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (c.read(figureContextProvider(noteId)).index.entries.isNotEmpty) {
        break;
      }
    }
    final ctx = sub.read();
    expect(ctx.chapter, chapter);
    expect(ctx.index.nameOf(FigureKind.figure, label), name);
    sub.close();
  }

  test('outside a project: plain n, tables counted apart', () {
    final index = buildFigureIndex([
      FigureNote(
        noteId: 'a',
        title: 'A',
        content: _c('{#fig:x} a\n{#tbl:y} b\n{#fig:z} c'),
      ),
    ]);
    expect(index.entries.map((e) => e.name), [
      'Figure 1',
      'Table 1',
      'Figure 2',
    ]);
    expect(index.nameOf(FigureKind.figure, 'nope'), 'Figure ??');
    expect(index.resolve('see {@fig:z}, {@tbl:q}'), 'see Figure 2, Table ??');
  });

  test('chapter prefix follows the chapter order', () async {
    await note('a', _c('{#fig:fa} A'));
    await note('b', _c('{#fig:fb} B\n{#fig:fc} C'));
    final p = await project('Thesis', DateTime(2026, 1, 1));
    await addNoteToProject(db, projectId: p, noteId: 'a');
    await addNoteToProject(db, projectId: p, noteId: 'b');
    await reorderChapters(db, p, ['a', 'b']);

    var index = await figureIndexForNote(db, 'b');
    expect(index.nameOf(FigureKind.figure, 'fa'), 'Figure 1.1');
    expect(index.nameOf(FigureKind.figure, 'fc'), 'Figure 2.2');

    await reorderChapters(db, p, ['b', 'a']);
    index = await figureIndexForNote(db, 'b');
    expect(index.nameOf(FigureKind.figure, 'fa'), 'Figure 2.1');
    expect(index.nameOf(FigureKind.figure, 'fc'), 'Figure 1.2');
    await expectNumber('a', 'fa', '2', 'Figure 2.1');
  });

  test('live content replaces the saved copy', () async {
    await note('a', _c('{#fig:fa} A'));
    final index = await figureIndexForNote(
      db,
      'a',
      liveContent: _c('{#fig:new} N\n{#fig:fa} A'),
    );
    expect(index.nameOf(FigureKind.figure, 'fa'), 'Figure 2');
    expect(index.nameOf(FigureKind.figure, 'new'), 'Figure 1');
  });

  test('a note in several projects uses the first by creation date', () async {
    await note('a', _c('{#fig:x} A'));
    await note('b', _c('{#fig:y} B'));
    final late = await project('Late', DateTime(2026, 6, 1));
    final early = await project('Early', DateTime(2026, 1, 1));
    await addNoteToProject(db, projectId: late, noteId: 'b');
    await addNoteToProject(db, projectId: late, noteId: 'a');
    await reorderChapters(db, late, ['b', 'a']);
    await addNoteToProject(db, projectId: early, noteId: 'a');
    // In Early, 'a' is chapter 1; in Late it would be chapter 2.
    final index = await figureIndexForNote(db, 'a');
    expect(index.nameOf(FigureKind.figure, 'x'), 'Figure 1.1');
    await expectNumber('a', 'x', '1', 'Figure 1.1');
  });

  test('offset of a definition matches the editor document', () {
    final stored = _c('Hi [@k] \$x\$\n{#fig:q} Cap');
    final off = figureOffset(stored, FigureKind.figure, 'q')!;
    // "Hi " + 2 chips + " " + newline => the chip starts at 3+1+1+1+1.
    expect(off, 7);
    expect(figureOffset(stored, FigureKind.figure, 'none'), isNull);
  });
}
