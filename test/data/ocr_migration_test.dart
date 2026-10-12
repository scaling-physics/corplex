import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('v12 -> v13 keeps data and adds the local-only OCR tables', () async {
    final dir = Directory.systemTemp.createTempSync('v13_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh
        .into(fresh.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'Old'));
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    raw.execute('DROP TABLE ocr_pages');
    raw.execute('DROP TABLE ocr_papers');
    raw.execute('PRAGMA user_version = 12');
    raw.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (d) => d.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    expect((await db.select(db.papers).getSingle()).title, 'Old');
    expect(await db.select(db.ocrPages).get(), isEmpty);

    await db
        .into(db.ocrPages)
        .insert(
          OcrPagesCompanion.insert(
            paperId: 'p1',
            pageNumber: 1,
            content: const Value('hello'),
          ),
        );
    // Not synced: nothing queued for upload.
    final dirty = await db
        .customSelect(
          "SELECT COUNT(*) c FROM sync_dirty WHERE table_name LIKE 'ocr%'",
        )
        .getSingle();
    expect(dirty.read<int>('c'), 0);
  });

  test('deleting a paper deletes its recognised text', () async {
    final db = AppDatabase.inMemoryForTesting();
    addTearDown(db.close);
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'P'));
    await db
        .into(db.ocrPapers)
        .insert(OcrPapersCompanion.insert(paperId: 'p1', pageCount: 2));
    await db
        .into(db.ocrPages)
        .insert(OcrPagesCompanion.insert(paperId: 'p1', pageNumber: 1));
    await db.delete(db.papers).go();
    expect(await db.select(db.ocrPages).get(), isEmpty);
    expect(await db.select(db.ocrPapers).get(), isEmpty);
  });
}
