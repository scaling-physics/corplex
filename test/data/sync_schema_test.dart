import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';

import 'v4_schema.dart';

Future<int> _tombstoneCount(AppDatabase db, [String? table]) async {
  final rows = await db
      .customSelect(
        table == null
            ? 'SELECT COUNT(*) AS c FROM sync_tombstones'
            : "SELECT COUNT(*) AS c FROM sync_tombstones WHERE table_name = '$table'",
      )
      .getSingle();
  return rows.read<int>('c');
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.inMemoryForTesting());
  tearDown(() => db.close());

  test('updating a row bumps updated_at when the writer did not', () async {
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            id: const Value('f1'),
            name: 'Old',
            updatedAt: Value(DateTime.utc(2020)),
          ),
        );

    await (db.update(db.folders)..where((f) => f.id.equals('f1'))).write(
      const FoldersCompanion(name: Value('New')),
    );

    final folder = await db.select(db.folders).getSingle();
    expect(folder.updatedAt.year, greaterThan(2020));
  });

  test('an explicit updated_at is left alone', () async {
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    final stamp = DateTime.utc(2031, 5, 5);

    await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(title: const Value('x'), updatedAt: Value(stamp)),
    );

    expect((await db.select(db.notes).getSingle()).updatedAt.toUtc(), stamp);
  });

  test('deleting a row records a tombstone, including FK cascades', () async {
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t1'), name: 'ml'));
    await db
        .into(db.noteTags)
        .insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1'));

    await (db.delete(db.notes)..where((n) => n.id.equals('n1'))).go();

    expect(await _tombstoneCount(db, 'notes'), 1);
    expect(await _tombstoneCount(db, 'note_tags'), 1);
  });

  test('re-linking a join row clears its tombstone', () async {
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t1'), name: 'ml'));
    final link = NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1');
    await db.into(db.noteTags).insert(link);
    await db.delete(db.noteTags).go();
    expect(await _tombstoneCount(db, 'note_tags'), 1);

    await db.into(db.noteTags).insert(link);

    expect(await _tombstoneCount(db, 'note_tags'), 0);
  });

  test(
    'migrating a v4 database keeps its data and adds sync tracking',
    () async {
      // The shared setUp database is intentionally alongside this one.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final old = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA foreign_keys = ON;');
            for (final statement in v4SchemaStatements) {
              raw.execute(statement);
            }
            raw.execute(
              "INSERT INTO papers (id, title, created_at) VALUES ('p1', 'Old paper', 1000)",
            );
            raw.execute(
              "INSERT INTO folders (id, name, created_at) VALUES ('f1', 'Thesis', 2000)",
            );
            raw.execute(
              "INSERT INTO notes (id, title) VALUES ('n1', 'Old note')",
            );
            raw.execute(
              "INSERT INTO note_paper_refs (note_id, paper_id) VALUES ('n1', 'p1')",
            );
            raw.execute('PRAGMA user_version = 4;');
          },
        ),
      );
      addTearDown(old.close);

      final paper = await old.select(old.papers).getSingle();
      expect(paper.title, 'Old paper');
      // Backfilled from created_at rather than left at the ALTER default.
      expect(
        paper.updatedAt.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000, isUtc: true),
      );
      expect((await old.select(old.folders).getSingle()).name, 'Thesis');
      expect(await old.select(old.notePaperRefs).get(), hasLength(1));

      // Triggers exist after migration.
      await old.delete(old.papers).go();
      expect(await _tombstoneCount(old, 'papers'), 1);
      expect(await _tombstoneCount(old, 'note_paper_refs'), 1);
    },
  );
}
