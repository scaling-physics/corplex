import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/study_details.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('v14 -> v15 keeps papers and syncs the study details', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('v15_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh
        .into(fresh.papers)
        .insert(PapersCompanion.insert(id: const Value('p'), title: 'Kept'));
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    for (final t in raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'trigger'",
    )) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    for (final c in [
      'species',
      'brain_regions',
      'techniques',
      'sample_size',
      'paradigm',
    ]) {
      raw.execute('ALTER TABLE papers DROP COLUMN $c');
    }
    raw.execute('ALTER TABLE matrix_columns DROP COLUMN paper_field');
    raw.execute('DELETE FROM sync_dirty');
    raw.execute('PRAGMA user_version = 14');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final paper = await db.select(db.papers).getSingle();
    expect(paper.title, 'Kept');
    expect(paper.species, isNull);
    expect(paper.sampleSize, isNull);

    Future<int> dirty() async =>
        (await db
                .customSelect(
                  "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'papers'",
                )
                .getSingle())
            .read<int>('c');
    expect(dirty(), completion(0), reason: 'the migration queues nothing');

    await setStudyValue(db, 'p', StudyField.species, 'mouse; rat');
    await setStudyValue(db, 'p', StudyField.sampleSize, '24');
    final after = await db.select(db.papers).getSingle();
    expect(after.species, 'mouse; rat');
    expect(after.sampleSize, 24);
    expect(await dirty(), 1);
  });
}
