import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('v20 -> v21 keeps notes, adds note_previews and its triggers', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = Directory.systemTemp.createTempSync('v21_migration');
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
    raw.execute('DROP TRIGGER note_previews_stale_upd');
    raw.execute('DROP TRIGGER note_previews_stale_ins');
    raw.execute('DROP TABLE note_previews');
    raw.execute('PRAGMA user_version = 20');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final note = await db.select(db.notes).getSingle();
    expect((note.title, note.content), ('Old note', '[{"insert":"hi\\n"}]'));
    expect(await db.select(db.notePreviews).get(), isEmpty);

    // The trigger exists and works.
    await db
        .into(db.notePreviews)
        .insert(NotePreviewsCompanion.insert(noteId: 'n1'));
    await db.customStatement("UPDATE notes SET content = 'x' WHERE id = 'n1'");
    expect(await db.select(db.notePreviews).get(), isEmpty);

    // And it leaves change tracking alone: previews are not synced.
    final tracked = await db
        .customSelect(
          "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'note_previews'",
        )
        .getSingle();
    expect(tracked.read<int>('c'), 0);
  });
}
