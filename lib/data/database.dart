import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(annotations);
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
