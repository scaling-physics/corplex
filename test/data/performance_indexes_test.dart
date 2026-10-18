import 'package:corplex/data/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.inMemoryForTesting());
  tearDown(() => db.close());

  Future<Set<String>> indexNames() async => {
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name LIKE 'idx_%'",
            )
            .get())
      r.read<String>('name'),
  };

  Future<String> plan(String sql) async => [
    for (final r in await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
      r.read<String>('detail'),
  ].join(' | ');

  test(
    'the local indexes exist after opening, and opening twice is fine',
    () async {
      final names = await indexNames();
      for (final statement in performanceIndexStatements) {
        final name = RegExp(r'idx_\w+').firstMatch(statement)!.group(0)!;
        expect(names, contains(name));
      }
      // Idempotent: a second run (the next launch) changes nothing.
      for (final statement in performanceIndexStatements) {
        await db.customStatement(statement);
      }
      expect(await indexNames(), names);
    },
  );

  test('queries use them instead of scanning', () async {
    expect(
      await plan("SELECT * FROM notes WHERE folder_id = 'f'"),
      contains('idx_notes_folder'),
    );
    expect(
      await plan(
        "SELECT * FROM highlights WHERE paper_id = 'p' ORDER BY page_number",
      ),
      contains('idx_highlights_paper_page'),
    );
    expect(
      await plan("SELECT * FROM attachments WHERE note_id = 'n'"),
      contains('idx_attachments_note'),
    );
    expect(
      await plan("SELECT * FROM note_tags WHERE tag_id = 't'"),
      contains('idx_note_tags_tag'),
    );
  });

  test('indexes do not disturb change tracking or tombstones', () async {
    await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(id: const Value('f'), name: 'F'));
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            folderId: const Value('f'),
          ),
        );
    final dirty = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_dirty')
        .getSingle();
    expect(dirty.read<int>('c'), greaterThan(0));
    // Deleting the folder nulls the note's folder (an indexed column).
    await (db.delete(db.folders)..where((f) => f.id.equals('f'))).go();
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals('n'))).getSingle();
    expect(note.folderId, isNull);
    final tomb = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_tombstones')
        .getSingle();
    expect(tomb.read<int>('c'), 1);
  });
}
