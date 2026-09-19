import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tables/annotations_table.dart';
import 'tables/attachments_table.dart';
import 'tables/folders_table.dart';
import 'tables/note_paper_refs_table.dart';
import 'tables/note_tags_table.dart';
import 'tables/notes_table.dart';
import 'tables/papers_table.dart';
import 'tables/tags_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Notes,
    Papers,
    Attachments,
    NotePaperRefs,
    Annotations,
    Folders,
    Tags,
    NoteTags,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  /// An in-memory database for tests, with foreign key enforcement turned
  /// on — SQLite has it off by default per-connection, so without this,
  /// FK actions like `ON DELETE SET NULL`/`CASCADE` silently don't fire
  /// and tests exercising them would pass for the wrong reason.
  factory AppDatabase.inMemoryForTesting() {
    return AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (database) => database.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
  }

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(annotations);
      }
      if (from < 3) {
        // v3 switched every table's primary key from an autoincrement int
        // to a client-generated UUID (required so IDs created offline on
        // different devices never collide once sync exists). There's no
        // production data yet, so upgrading rebuilds the schema fresh
        // rather than migrating existing rows to new IDs.
        for (final table in <TableInfo>[
          annotations,
          attachments,
          notePaperRefs,
          papers,
          notes,
        ]) {
          await m.deleteTable(table.actualTableName);
        }
        await m.createAll();
      }
      if (from < 4) {
        // v4 adds folders and tags — purely additive, no existing data
        // needs to change.
        await m.createTable(folders);
        await m.createTable(tags);
        await m.createTable(noteTags);
        await m.addColumn(notes, notes.folderId);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'corplex.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (database) => database.execute('PRAGMA foreign_keys = ON;'),
    );
  });
}
