/// Describes which local tables and columns take part in cloud sync, and
/// the SQLite triggers that record local changes for the sync engine.
///
/// Sync is last-write-wins per row, keyed on `updated_at`. Rather than
/// touching every query in the app, change tracking lives in the database:
///
/// * an AFTER UPDATE trigger moves `updated_at` forward when the writer
///   didn't (never backwards, even past a skewed clock);
/// * AFTER INSERT/UPDATE triggers mark the row in `sync_dirty` (updates
///   only when a *synced* column changed), the queue
///   of rows still to be pushed (an explicit queue, not a timestamp
///   cursor, because `updated_at` only has one-second resolution);
/// * an AFTER DELETE trigger records a tombstone in `sync_tombstones`
///   (FK cascades fire it too), so deletes can be pushed to other devices;
/// * the first local edit of a row since it last synced saves the row as it
///   was in `sync_base`, so if another device edited it too the engine can
///   merge the two edits instead of keeping only the later one
///   (`features/sync/merge.dart`).
///
/// All of them stay quiet while `sync_meta.applying = 1`, which is how
/// the engine applies rows pulled from the server without echoing them
/// back as local edits.
library;

/// Column names are the snake_case names drift generates, which the
/// Supabase schema (supabase/migrations) mirrors exactly.
class SyncTableSpec {
  const SyncTableSpec(this.name, {required this.keys, required this.columns});

  final String name;

  /// Primary key columns (`id`, or the two FKs of a join table).
  final List<String> keys;

  /// Every other synced column. Device-local columns (file paths) are
  /// deliberately absent — they mean nothing on another device.
  final List<String> columns;

  List<String> get allColumns => [...keys, ...columns];

  /// Rows with a single `id` key are three-way merged on conflict. A join
  /// row has no content to merge: it exists or it doesn't.
  bool get mergeable => keys.length == 1 && keys.single == 'id';
}

/// Columns holding a DateTime, stored locally as unix seconds and remotely
/// as `timestamptz`.
const syncDateTimeColumns = {'created_at', 'updated_at', 'due_date'};

/// Ordered parents-before-children so foreign keys are satisfied when
/// applying pulled rows; deletes are applied in the reverse order.
const syncTables = [
  SyncTableSpec(
    'folders',
    keys: ['id'],
    columns: ['name', 'created_at', 'updated_at'],
  ),
  SyncTableSpec(
    'tags',
    keys: ['id'],
    columns: ['name', 'created_at', 'updated_at'],
  ),
  SyncTableSpec(
    'papers',
    keys: ['id'],
    columns: [
      'title',
      'authors',
      'year',
      'venue',
      'doi',
      'storage_key',
      'last_page',
      'page_count',
      'reading_status',
      'citekey',
      'rating',
      'species',
      'brain_regions',
      'techniques',
      'sample_size',
      'paradigm',
      'pmid',
      'url',
      'abstract',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'projects',
    keys: ['id'],
    columns: ['name', 'due_date', 'created_at', 'updated_at'],
  ),
  SyncTableSpec(
    'notes',
    keys: ['id'],
    columns: [
      'title',
      'content',
      'folder_id',
      'pinned',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'note_versions',
    keys: ['id'],
    columns: [
      'note_id',
      'title',
      'content',
      'label',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'note_comments',
    keys: ['id'],
    columns: [
      'note_id',
      'quote',
      'anchor',
      'body',
      'author',
      'resolved',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'note_keys',
    keys: ['id'],
    columns: [
      'kdf',
      'iterations',
      'salt',
      'wrapped_key',
      'hint',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'note_tags',
    keys: ['note_id', 'tag_id'],
    columns: ['updated_at'],
  ),
  SyncTableSpec(
    'note_paper_refs',
    keys: ['note_id', 'paper_id'],
    columns: ['updated_at'],
  ),
  SyncTableSpec(
    'project_papers',
    keys: ['project_id', 'paper_id'],
    columns: ['updated_at'],
  ),
  SyncTableSpec(
    'project_notes',
    keys: ['project_id', 'note_id'],
    columns: ['position', 'status', 'word_target', 'updated_at'],
  ),
  SyncTableSpec(
    'matrix_columns',
    keys: ['id'],
    columns: [
      'project_id',
      'name',
      'position',
      'paper_field',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'matrix_cells',
    keys: ['column_id', 'paper_id'],
    columns: ['text', 'updated_at'],
  ),
  SyncTableSpec(
    'attachments',
    keys: ['id'],
    columns: [
      'note_id',
      'paper_id',
      'type',
      'title',
      'url',
      'storage_key',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'highlights',
    keys: ['id'],
    columns: [
      'paper_id',
      'page_number',
      'quote',
      'rects_json',
      'color_hex',
      'comment',
      'created_at',
      'updated_at',
    ],
  ),
  SyncTableSpec(
    'annotations',
    keys: ['id'],
    columns: [
      'paper_id',
      'page_number',
      'color_hex',
      'points_json',
      'created_at',
      'updated_at',
    ],
  ),
];

const _now = "CAST(strftime('%s', 'now') AS INTEGER)";
const _notApplying = '(SELECT applying FROM sync_meta WHERE id = 1) = 0';

/// Idempotent DDL for the sync bookkeeping tables and change-tracking
/// triggers. Run on create and on upgrade to schema v5.
///
/// [existingTables] limits the per-table triggers to tables that exist:
/// an upgrade step runs this before later steps have created newer tables,
/// and those steps call it again once they have.
///
/// [markExisting] queues every existing row for upload, which a step adding
/// synced tables or columns needs; a step that only changes triggers
/// doesn't.
List<String> syncSchemaStatements({
  Set<String>? existingTables,
  bool markExisting = true,
}) {
  final statements = <String>[
    'CREATE TABLE IF NOT EXISTS sync_meta ('
        'id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1), '
        'applying INTEGER NOT NULL DEFAULT 0, '
        'user_id TEXT, '
        'last_pull TEXT)',
    'INSERT OR IGNORE INTO sync_meta (id) VALUES (1)',
    'CREATE TABLE IF NOT EXISTS sync_tombstones ('
        'table_name TEXT NOT NULL, '
        'row_key TEXT NOT NULL, '
        'deleted_at INTEGER NOT NULL, '
        'PRIMARY KEY (table_name, row_key))',
    // `id` doubles as a sequence number: re-marking a row replaces its
    // entry with a higher id, so clearing an entry after a push (by id)
    // never drops an edit made while the push was in flight.
    'CREATE TABLE IF NOT EXISTS sync_dirty ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'table_name TEXT NOT NULL, '
        'row_key TEXT NOT NULL, '
        'UNIQUE (table_name, row_key))',
    // The last-synced version of a row with unpushed local edits, as a JSON
    // object of its synced columns (see [SyncTableSpec.mergeable]).
    'CREATE TABLE IF NOT EXISTS sync_base ('
        'table_name TEXT NOT NULL, '
        'row_key TEXT NOT NULL, '
        'data TEXT NOT NULL, '
        'PRIMARY KEY (table_name, row_key))',
  ];

  for (final t in syncTables) {
    if (existingTables != null && !existingTables.contains(t.name)) continue;
    final oldKey = t.keys.map((k) => "'$k', OLD.$k").join(', ');
    final newKey = t.keys.map((k) => "'$k', NEW.$k").join(', ');
    final rowKey = t.keys.map((k) => "'$k', $k").join(', ');
    // Only changes to synced columns are edits. Device-local columns (a
    // PDF's path on this device) must not mark the row as changed, or
    // setting them would push the row and could override a real edit made
    // on another device.
    final changed = t.allColumns
        .where((c) => c != 'updated_at')
        .map((c) => 'NEW.$c IS NOT OLD.$c')
        .join(' OR ');
    // Delete-then-insert rather than INSERT OR REPLACE: when a trigger
    // fires from an outer statement (e.g. an FK action), SQLite overrides
    // the trigger's own ON CONFLICT clause with the outer one.
    final markDirty =
        "DELETE FROM sync_dirty WHERE table_name = '${t.name}' "
        'AND row_key = json_object($newKey); '
        'INSERT INTO sync_dirty (table_name, row_key) '
        "VALUES ('${t.name}', json_object($newKey))";
    // Only the *first* edit since the last sync records the base; later
    // edits before the push keep it.
    final oldRow = t.allColumns.map((c) => "'$c', OLD.$c").join(', ');
    final saveBase = t.mergeable
        ? 'INSERT INTO sync_base (table_name, row_key, data) '
              "SELECT '${t.name}', json_object($oldKey), json_object($oldRow) "
              'WHERE NOT EXISTS (SELECT 1 FROM sync_base '
              "WHERE table_name = '${t.name}' "
              'AND row_key = json_object($oldKey)); '
        : '';

    statements.addAll([
      // Anything that predates sync (or was written while signed out)
      // still needs uploading.
      if (markExisting)
        'INSERT OR IGNORE INTO sync_dirty (table_name, row_key) '
            "SELECT '${t.name}', json_object($rowKey) FROM ${t.name}",
      'DROP TRIGGER IF EXISTS sync_${t.name}_ins',
      'CREATE TRIGGER sync_${t.name}_ins AFTER INSERT ON ${t.name} '
          'WHEN $_notApplying BEGIN $markDirty; '
          // A join row can be unlinked and later re-linked with the same
          // key; the re-link supersedes the earlier tombstone.
          "DELETE FROM sync_tombstones WHERE table_name = '${t.name}' "
          'AND row_key = json_object($newKey); END',
      'DROP TRIGGER IF EXISTS sync_${t.name}_upd_dirty',
      'CREATE TRIGGER sync_${t.name}_upd_dirty AFTER UPDATE ON ${t.name} '
          'WHEN $_notApplying AND ($changed) BEGIN $saveBase$markDirty; END',
      'DROP TRIGGER IF EXISTS sync_${t.name}_upd',
      // An edit must always move updated_at forward: to now, or — if the
      // row carries a later time from another device's clock — one second
      // past it. Otherwise the edit could lose to older data.
      'CREATE TRIGGER sync_${t.name}_upd AFTER UPDATE ON ${t.name} '
          'WHEN NEW.updated_at <= OLD.updated_at AND $_notApplying '
          'AND ($changed) BEGIN '
          'UPDATE ${t.name} SET updated_at = MAX($_now, OLD.updated_at + 1) '
          'WHERE rowid = NEW.rowid; END',
      'DROP TRIGGER IF EXISTS sync_${t.name}_del',
      'CREATE TRIGGER sync_${t.name}_del AFTER DELETE ON ${t.name} '
          'WHEN $_notApplying BEGIN '
          "DELETE FROM sync_dirty WHERE table_name = '${t.name}' "
          'AND row_key = json_object($oldKey); '
          "DELETE FROM sync_tombstones WHERE table_name = '${t.name}' "
          'AND row_key = json_object($oldKey); '
          "DELETE FROM sync_base WHERE table_name = '${t.name}' "
          'AND row_key = json_object($oldKey); '
          'INSERT INTO sync_tombstones '
          "(table_name, row_key, deleted_at) VALUES ('${t.name}', "
          'json_object($oldKey), $_now); END',
    ]);
  }
  return statements;
}
