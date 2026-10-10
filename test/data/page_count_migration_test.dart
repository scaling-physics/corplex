import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('v11 -> v12 keeps data, adds page_count and syncs it', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('v12_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // Build a current database, then turn it back into a v11 one.
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh
        .into(fresh.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Old paper',
            lastPage: const Value(4),
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    final triggers = raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'trigger'",
    );
    for (final t in triggers) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    raw.execute('ALTER TABLE papers DROP COLUMN page_count');
    raw.execute('DELETE FROM sync_dirty');
    raw.execute('PRAGMA user_version = 11');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final paper = await db.select(db.papers).getSingle();
    expect(
      (paper.title, paper.lastPage, paper.pageCount),
      ('Old paper', 4, null),
    );
    // Not re-queued by the migration itself.
    expect(
      (await db.customSelect('SELECT COUNT(*) c FROM sync_dirty').getSingle())
          .read<int>('c'),
      0,
    );

    // The rebuilt update trigger treats page_count as a synced edit.
    await (db.update(db.papers))
        .write(const PapersCompanion(pageCount: Value(12)));
    expect(
      (await db
              .customSelect(
                "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'papers'",
              )
              .getSingle())
          .read<int>('c'),
      1,
    );
  });
}
