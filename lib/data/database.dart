import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'backup.dart';
import 'sync_schema.dart';
import 'tables/annotations_table.dart';
import 'tables/attachments_table.dart';
import 'tables/folders_table.dart';
import 'tables/highlights_table.dart';
import 'tables/note_paper_refs_table.dart';
import 'tables/note_tags_table.dart';
import 'tables/notes_table.dart';
import 'tables/papers_table.dart';
import 'tables/projects_table.dart';
import 'tables/tags_table.dart';
import 'tables/trash_table.dart';

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
    Highlights,
    Projects,
    ProjectPapers,
    ProjectNotes,
    TrashItems,
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
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSyncSchema();
    },
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
        // Guarded: a database upgraded from <3 was rebuilt with the
        // current schema above, so these may already exist.
        for (final table in <TableInfo>[folders, tags, noteTags]) {
          if (!await _hasTable(table.actualTableName)) {
            await m.createTable(table);
          }
        }
        if (!await _hasColumn('notes', 'folder_id')) {
          await m.addColumn(notes, notes.folderId);
        }
      }
      if (from < 5) {
        // v5 adds `updated_at` everywhere (last-write-wins sync needs it)
        // plus the sync bookkeeping tables and change-tracking triggers.
        // ALTER TABLE can't add a column defaulting to "now", so existing
        // rows get 0 and are then backfilled from `created_at`; new rows
        // always get their value from drift's clientDefault.
        for (final table in ['papers', 'attachments', 'annotations']) {
          await _addUpdatedAt(table, backfillFrom: 'created_at');
        }
        for (final table in ['folders', 'tags']) {
          await _addUpdatedAt(table, backfillFrom: 'created_at');
        }
        for (final table in ['note_tags', 'note_paper_refs']) {
          await _addUpdatedAt(table);
        }
        await _createSyncSchema();
      }
      if (from < 6) {
        // v6 adds cloud-storage keys so files can sync. Guarded because a
        // database upgraded from <3 was rebuilt with the current schema.
        for (final (table, column) in [
          ('papers', 'storage_key'),
          ('attachments', 'storage_key'),
        ]) {
          if (!await _hasColumn(table, column)) {
            await customStatement('ALTER TABLE $table ADD COLUMN $column TEXT');
          }
        }
      }
      if (from < 7) {
        // v7: text highlights, and per-paper reading position/status.
        if (!await _hasTable('highlights')) await m.createTable(highlights);
        if (!await _hasColumn('papers', 'last_page')) {
          await m.addColumn(papers, papers.lastPage);
        }
        if (!await _hasColumn('papers', 'reading_status')) {
          await m.addColumn(papers, papers.readingStatus);
        }
        // Change-tracking triggers for the new table (idempotent).
        await _createSyncSchema();
      }
      if (from < 8) {
        // v8: projects (groups of papers and notes).
        for (final table in <TableInfo>[projects, projectPapers, projectNotes]) {
          if (!await _hasTable(table.actualTableName)) {
            await m.createTable(table);
          }
        }
        await _createSyncSchema();
      }
      if (from < 9) {
        // v9: local-only trash (not part of sync).
        if (!await _hasTable('trash_items')) await m.createTable(trashItems);
      }
    },
  );

  Future<bool> _hasTable(String table) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(String table, String column) async {
    final columns = await customSelect('PRAGMA table_info($table)').get();
    return columns.any((c) => c.read<String>('name') == column);
  }

  Future<void> _addUpdatedAt(String table, {String? backfillFrom}) async {
    if (await _hasColumn(table, 'updated_at')) return;
    await customStatement(
      'ALTER TABLE $table ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
    );
    await customStatement(
      backfillFrom == null
          ? "UPDATE $table SET updated_at = CAST(strftime('%s','now') AS INTEGER)"
          : 'UPDATE $table SET updated_at = $backfillFrom',
    );
  }

  Future<void> _createSyncSchema() async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    final existing = {for (final t in tables) t.read<String>('name')};
    for (final statement in syncSchemaStatements(existingTables: existing)) {
      await customStatement(statement);
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    // A restored backup is swapped in here, before the database opens.
    await applyPendingRestore(dbFolder);
    final file = File(p.join(dbFolder.path, 'corplex.sqlite'));
    return NativeDatabase.createInBackground(
      file,
      setup: (database) => database.execute('PRAGMA foreign_keys = ON;'),
    );
  });
}
