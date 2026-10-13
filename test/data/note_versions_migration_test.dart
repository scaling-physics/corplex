import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/note_versions.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('v15 -> v16 keeps notes and syncs the new versions table', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('v16_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh
        .into(fresh.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Kept'),
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(file.path);
    for (final t in raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'trigger'",
    )) {
      raw.execute('DROP TRIGGER "${t['name']}"');
    }
    raw.execute('DROP TABLE note_versions');
    raw.execute('DELETE FROM sync_dirty');
    raw.execute('PRAGMA user_version = 15');
    raw.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (d) => d.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    expect((await db.select(db.notes).getSingle()).title, 'Kept');
    expect(await db.select(db.noteVersions).get(), isEmpty);

    Future<int> dirty() async =>
        (await db
                .customSelect(
                  "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'note_versions'",
                )
                .getSingle())
            .read<int>('c');
    expect(await dirty(), 0, reason: 'the migration queues nothing');

    await saveNoteVersion(db, 'n', label: 'First');
    expect(await dirty(), 1);
    final v = await db.select(db.noteVersions).getSingle();
    expect(v.title, 'Kept');

    // Deleting the note cascades, and the delete is recorded for sync.
    await (db.delete(db.notes)..where((n) => n.id.equals('n'))).go();
    expect(await db.select(db.noteVersions).get(), isEmpty);
    final tombstones = await db
        .customSelect(
          "SELECT COUNT(*) c FROM sync_tombstones WHERE table_name = 'note_versions'",
        )
        .getSingle();
    expect(tombstones.read<int>('c'), 1);
  });
}
