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
import 'tables/matrix_table.dart';
import 'tables/note_keys_table.dart';
import 'tables/note_paper_refs_table.dart';
import 'tables/note_previews_table.dart';
import 'tables/note_tags_table.dart';
import 'tables/note_comments_table.dart';
import 'tables/note_versions_table.dart';
import 'tables/ocr_table.dart';
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
    MatrixColumns,
    MatrixCells,
    NoteVersions,
    NoteKeys,
    NoteComments,
    TrashItems,
    OcrPages,
    OcrPapers,
    NotePreviews,
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
        setup: (database) {
          database.execute('PRAGMA foreign_keys = ON;');
          database.execute('PRAGMA secure_delete = ON;');
        },
      ),
    );
  }

  @override
  int get schemaVersion => 21;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSyncSchema();
    },
    beforeOpen: (details) async {
      await _createPerformanceIndexes();
      await _createNotePreviewTriggers();
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
        for (final table in <TableInfo>[
          projects,
          projectPapers,
          projectNotes,
        ]) {
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
      if (from < 10) {
        // v10: citekeys and ratings on papers; the synthesis matrix.
        if (!await _hasColumn('papers', 'citekey')) {
          await m.addColumn(papers, papers.citekey);
        }
        if (!await _hasColumn('papers', 'rating')) {
          await m.addColumn(papers, papers.rating);
        }
        for (final table in <TableInfo>[matrixColumns, matrixCells]) {
          if (!await _hasTable(table.actualTableName)) {
            await m.createTable(table);
          }
        }
        await _createSyncSchema();
      }
      if (from < 11) {
        // v11: edits made on two devices are merged, which needs the
        // last-synced version of each locally edited row (`sync_base`,
        // saved by the update triggers). No new synced data, so nothing is
        // queued for upload again.
        await _createSyncSchema(markExisting: false);
      }
      if (from < 12) {
        // v12: page counts, for reading progress. Re-running the sync
        // schema rebuilds the update triggers so they compare the new
        // column. Nothing is queued: counts are filled in lazily and the
        // next edit of a row uploads them.
        if (!await _hasColumn('papers', 'page_count')) {
          await m.addColumn(papers, papers.pageCount);
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 13) {
        // v13: local-only OCR text for scanned PDFs (derived, not synced).
        for (final table in <TableInfo>[ocrPages, ocrPapers]) {
          if (!await _hasTable(table.actualTableName)) {
            await m.createTable(table);
          }
        }
      }
      if (from < 14) {
        // v14: thesis outline. Chapter order/status/target on project_notes
        // and a due date on projects, all synced. Positions stay null so
        // existing notes keep their (creation) order until reordered.
        for (final (table, column, type) in [
          ('project_notes', 'position', 'INTEGER'),
          ('project_notes', 'status', 'TEXT'),
          ('project_notes', 'word_target', 'INTEGER'),
          ('projects', 'due_date', 'INTEGER'),
        ]) {
          if (!await _hasColumn(table, column)) {
            await customStatement(
              'ALTER TABLE $table ADD COLUMN $column $type',
            );
          }
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 15) {
        // v15: study details on papers, and matrix columns bound to them.
        // All synced; nothing to backfill.
        for (final (table, column, type) in [
          ('papers', 'species', 'TEXT'),
          ('papers', 'brain_regions', 'TEXT'),
          ('papers', 'techniques', 'TEXT'),
          ('papers', 'sample_size', 'INTEGER'),
          ('papers', 'paradigm', 'TEXT'),
          ('matrix_columns', 'paper_field', 'TEXT'),
        ]) {
          if (!await _hasColumn(table, column)) {
            await customStatement(
              'ALTER TABLE $table ADD COLUMN $column $type',
            );
          }
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 16) {
        // v16: saved versions of a note. A new synced table; nothing to
        // backfill.
        if (!await _hasTable('note_versions')) {
          await m.createTable(noteVersions);
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 17) {
        // v17: the notes password (wrapped keys for locked notes). A new
        // synced table; locked note bodies live in `notes.content` as an
        // envelope, so no other table changes.
        if (!await _hasTable('note_keys')) {
          await m.createTable(noteKeys);
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 18) {
        // v18: pinned notes. A synced column, so the sync triggers are
        // rebuilt to watch it.
        if (!await _hasColumn('notes', 'pinned')) {
          await m.addColumn(notes, notes.pinned);
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 19) {
        // v19: comments on a passage of a note. A new synced table; nothing
        // to backfill.
        if (!await _hasTable('note_comments')) {
          await m.createTable(noteComments);
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 20) {
        // v20: a paper's PubMed id, web link and abstract. Synced columns,
        // so the sync triggers are rebuilt to watch them.
        for (final (name, column) in [
          ('pmid', papers.pmid),
          ('url', papers.url),
          ('abstract', papers.abstract),
        ]) {
          if (!await _hasColumn('papers', name)) {
            await m.addColumn(papers, column);
          }
        }
        await _createSyncSchema(markExisting: false);
      }
      if (from < 21) {
        // v21: stored previews for the Notes list (local-only, derived).
        // Empty on purpose: the list fills it as it shows notes.
        if (!await _hasTable('note_previews')) {
          await m.createTable(notePreviews);
        }
        await _createNotePreviewTriggers();
      }
    },
  );

  /// The triggers that keep `note_previews` honest (see [NotePreviews]).
  /// Idempotent, run on migration and every open.
  Future<void> _createNotePreviewTriggers() async {
    for (final statement in notePreviewStatements) {
      await customStatement(statement);
    }
  }

  /// Local-only indexes for the lookups the UI and the cascades make. They
  /// are not part of the synced schema and need no schema bump:
  /// `IF NOT EXISTS` makes them idempotent, so existing installs gain them
  /// the next time the database opens (and they ride along in backups
  /// harmlessly). Foreign-key columns matter twice: every `ON DELETE
  /// CASCADE`/`SET NULL` otherwise scans the child table.
  Future<void> _createPerformanceIndexes() async {
    for (final statement in performanceIndexStatements) {
      await customStatement(statement);
    }
  }

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

  Future<void> _createSyncSchema({bool markExisting = true}) async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    final existing = {for (final t in tables) t.read<String>('name')};
    for (final statement in syncSchemaStatements(
      existingTables: existing,
      markExisting: markExisting,
    )) {
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
      // secure_delete zeroes freed pages, so a note's plain text doesn't
      // linger in the file after the note is locked.
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON;');
        database.execute('PRAGMA secure_delete = ON;');
      },
    );
  });
}

/// See [AppDatabase._createPerformanceIndexes]. Composite indexes put the
/// equality column first, then the one the query sorts or filters by.
const performanceIndexStatements = <String>[
  // Notes list: folder filter, and the folder's ON DELETE SET NULL.
  'CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes (folder_id)',
  // Every notes list orders pinned first, newest edit first.
  'CREATE INDEX IF NOT EXISTS idx_notes_order ON notes (pinned DESC, updated_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_papers_created ON papers (created_at DESC)',
  // Join tables: the primary key covers the first column only.
  'CREATE INDEX IF NOT EXISTS idx_note_tags_tag ON note_tags (tag_id)',
  'CREATE INDEX IF NOT EXISTS idx_project_notes_note ON project_notes (note_id)',
  'CREATE INDEX IF NOT EXISTS idx_project_papers_paper ON project_papers (paper_id)',
  'CREATE INDEX IF NOT EXISTS idx_note_paper_refs_paper ON note_paper_refs (paper_id)',
  'CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments (note_id)',
  'CREATE INDEX IF NOT EXISTS idx_attachments_paper ON attachments (paper_id)',
  // The viewer asks for one page's marks at a time.
  'CREATE INDEX IF NOT EXISTS idx_highlights_paper_page ON highlights (paper_id, page_number)',
  'CREATE INDEX IF NOT EXISTS idx_annotations_paper_page ON annotations (paper_id, page_number)',
  'CREATE INDEX IF NOT EXISTS idx_note_versions_note ON note_versions (note_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_note_comments_note ON note_comments (note_id)',
  'CREATE INDEX IF NOT EXISTS idx_matrix_cells_paper ON matrix_cells (paper_id)',
];

/// A note's stored preview is deleted whenever its body changes or the row is
/// (re)inserted, so a missing row always means "recompute". Separate from the
/// sync triggers: these only touch `note_previews`, which isn't synced.
const notePreviewStatements = <String>[
  'CREATE TRIGGER IF NOT EXISTS note_previews_stale_upd '
      'AFTER UPDATE OF content ON notes '
      'BEGIN DELETE FROM note_previews WHERE note_id = NEW.id; END',
  'CREATE TRIGGER IF NOT EXISTS note_previews_stale_ins '
      'AFTER INSERT ON notes '
      'BEGIN DELETE FROM note_previews WHERE note_id = NEW.id; END',
];
