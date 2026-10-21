import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('v21 -> v22 keeps notes, adds note columns and saved_searches, '
      'and syncs them', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('v22_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh
        .into(fresh.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Old note'),
            content: const Value('[{"insert":"hi\\n"}]'),
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    raw.execute('DROP TABLE saved_searches');
    // A v21 database's triggers name no v22 columns; the migration
    // rebuilds them.
    final triggers = raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' "
      "AND tbl_name IN ('notes', 'saved_searches')",
    );
    for (final t in triggers) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    for (final c in ['daily_date', 'aliases', 'is_template']) {
      raw.execute('ALTER TABLE notes DROP COLUMN $c');
    }
    raw.execute('PRAGMA user_version = 21');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final note = await db.select(db.notes).getSingle();
    expect(note.title, 'Old note');
    expect(
      (note.dailyDate, note.aliases, note.isTemplate),
      (null, null, false),
    );
    await db.customStatement('DELETE FROM sync_dirty');

    // The new columns count as edits, and saved searches are tracked.
    await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
      const NotesCompanion(aliases: Value('Old; Older')),
    );
    await db
        .into(db.savedSearches)
        .insert(
          SavedSearchesCompanion.insert(
            id: const Value('s1'),
            name: 'Reading',
            query: 'tag:reading',
          ),
        );
    final tracked = await db
        .customSelect('SELECT table_name FROM sync_dirty ORDER BY table_name')
        .get();
    expect(tracked.map((r) => r.read<String>('table_name')), [
      'notes',
      'saved_searches',
    ]);
  });
}
