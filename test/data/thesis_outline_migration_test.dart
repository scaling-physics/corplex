import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test(
    'v13 -> v14 keeps chapters in order and syncs the new columns',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final dir = Directory.systemTemp.createTempSync('v14_migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/db.sqlite');

      final fresh = AppDatabase.forTesting(NativeDatabase(file));
      await fresh
          .into(fresh.projects)
          .insert(
            ProjectsCompanion.insert(id: const Value('pr'), name: 'Thesis'),
          );
      for (final (id, day) in [('b', 2), ('a', 1), ('c', 3)]) {
        await fresh
            .into(fresh.notes)
            .insert(
              NotesCompanion.insert(
                id: Value(id),
                title: Value('Note $id'),
                createdAt: Value(DateTime(2026, 1, day)),
              ),
            );
        await addLink(fresh, id);
      }
      await fresh.close();

      final raw = sql.sqlite3.open(file.path);
      for (final t in raw.select(
        "SELECT name FROM sqlite_master WHERE type = 'trigger'",
      )) {
        raw.execute('DROP TRIGGER "${t['name']}"');
      }
      raw.execute('ALTER TABLE project_notes DROP COLUMN position');
      raw.execute('ALTER TABLE project_notes DROP COLUMN status');
      raw.execute('ALTER TABLE project_notes DROP COLUMN word_target');
      raw.execute('ALTER TABLE projects DROP COLUMN due_date');
      raw.execute('DELETE FROM sync_dirty');
      raw.execute('PRAGMA user_version = 13');
      raw.close();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      expect(
        [for (final n in await orderedProjectNotes(db, 'pr')) n.id],
        ['a', 'b', 'c'],
        reason: 'unplaced rows keep creation order',
      );
      expect((await db.select(db.projects).getSingle()).dueDate, isNull);
      expect(
        (await db.customSelect('SELECT COUNT(*) c FROM sync_dirty').getSingle())
            .read<int>('c'),
        0,
      );

      Future<int> dirty(String table) async =>
          (await db
                  .customSelect(
                    'SELECT COUNT(*) c FROM sync_dirty WHERE table_name = ?',
                    variables: [Variable.withString(table)],
                  )
                  .getSingle())
              .read<int>('c');

      await setChapterStatus(db, 'pr', 'a', ChapterStatus.draft);
      expect(await dirty('project_notes'), 1);
      await setProjectDueDate(db, 'pr', DateTime(2027, 3, 14));
      expect(await dirty('projects'), 1);
    },
  );
}

Future<void> addLink(AppDatabase db, String noteId) => db
    .into(db.projectNotes)
    .insert(ProjectNotesCompanion.insert(projectId: 'pr', noteId: noteId));
