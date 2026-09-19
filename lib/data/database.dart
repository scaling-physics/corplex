import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tables/annotations_table.dart';
import 'tables/attachments_table.dart';
import 'tables/note_paper_refs_table.dart';
import 'tables/notes_table.dart';
import 'tables/papers_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Notes, Papers, Attachments, NotePaperRefs, Annotations],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

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
