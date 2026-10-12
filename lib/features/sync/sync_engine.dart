import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../data/sync_schema.dart';
import 'file_sync.dart';
import 'merge.dart';
import 'sync_remote.dart';

/// Thrown when the local database already belongs to a different account.
/// Syncing anyway would merge two people's libraries, so we refuse.
class SyncAccountMismatch implements Exception {
  const SyncAccountMismatch();

  @override
  String toString() =>
      'This device holds data from a different account. '
      'Sign back in to that account to sync.';
}

/// Thrown after a sync whose metadata succeeded but some files couldn't be
/// transferred; they're retried on the next sync.
class SyncFilesIncomplete implements Exception {
  const SyncFilesIncomplete();

  @override
  String toString() => 'Some files haven\'t synced yet.';
}

/// Two-way, last-write-wins sync between the local drift database and a
/// [SyncRemote]. One call to [sync] pushes local changes, then pulls
/// remote ones. Local storage stays the source of truth: nothing here is
/// needed for the app to work, and a failed sync leaves local data as is.
class SyncEngine {
  // A private field can't be a named initializing formal.
  // ignore: prefer_initializing_formals
  SyncEngine(this._db, this._remote, {FileSync? files}) : _files = files;

  final AppDatabase _db;
  final SyncRemote _remote;
  final FileSync? _files;

  static const _batchSize = 200;

  Future<void> sync({required String userId}) async {
    final meta = await _readMeta();

    if (meta.userId != null && meta.userId != userId) {
      throw const SyncAccountMismatch();
    }
    if (meta.userId == null) {
      // First sync on this device: adopt the signed-in account, which also
      // uploads anything created while signed out.
      await _db.customStatement('UPDATE sync_meta SET user_id = ?', [userId]);
    }

    final files = _files;
    files?.failures = 0;
    _skipped.clear();
    // Upload first so the storage keys go out in this same push.
    await files?.upload(userId);
    await _push();
    await _pull(meta.cursors);
    await files?.download();
    // Only with a complete picture of the server: nothing skipped.
    if (files != null && _skipped.isEmpty && files.failures == 0) {
      await files.removeOrphans(userId, await _remote.liveStorageKeys());
    }
    // Tables the server doesn't have (yet) were skipped, not fatal: their
    // changes stay queued here and everything else synced. Say so.
    if (_skipped.isNotEmpty) throw const SyncServerOutdated();
    if (files != null && files.failures > 0) throw const SyncFilesIncomplete();
  }

  /// Tables the server rejected as missing this round. Syncing carries on
  /// without them, so one un-migrated table doesn't block the whole
  /// library; their queued changes wait for the migration.
  final _skipped = <String>{};

  /// Runs [action] for [table] unless the server is known to lack it;
  /// a "missing table/column" answer marks it skipped instead of failing.
  Future<void> _unlessOutdated(
    String table,
    Future<void> Function() action,
  ) async {
    if (_skipped.contains(table)) return;
    try {
      await action();
    } on SyncServerOutdated {
      _skipped.add(table);
    }
  }

  /// Fetches one file on request (see [FileSync.fetchPaper]).
  Future<bool> fetchFile({String? paperId, String? attachmentId}) async {
    final files = _files;
    if (files == null) return false;
    if (paperId != null) return files.fetchPaper(paperId);
    if (attachmentId != null) return files.fetchAttachment(attachmentId);
    return false;
  }

  /// Changes that exist only on this device: unpushed edits, unpushed
  /// deletes, and files not yet uploaded.
  Future<int> pendingChanges() async {
    final row = await _db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM sync_dirty) + '
          '(SELECT COUNT(*) FROM sync_tombstones) AS c',
        )
        .getSingle();
    return row.read<int>('c') + (await _files?.pendingUploads() ?? 0);
  }

  /// Deletes everything on this device — rows, sync bookkeeping and the
  /// downloaded files — and forgets which account it belonged to, so the
  /// next sign-in starts clean. Anything not yet synced is lost.
  Future<void> eraseLocalData() async {
    final paths = <String>[
      for (final r
          in await _db
              .customSelect(
                'SELECT pdf_path AS p FROM papers WHERE pdf_path IS NOT NULL',
              )
              .get())
        r.read<String>('p'),
      for (final r
          in await _db
              .customSelect(
                'SELECT path AS p FROM attachments WHERE path IS NOT NULL',
              )
              .get())
        r.read<String>('p'),
    ];

    await _db.transaction(() async {
      await _db.customStatement('UPDATE sync_meta SET applying = 1');
      try {
        for (final table in syncTables.reversed) {
          await _db.customStatement('DELETE FROM ${table.name}');
        }
      } finally {
        await _db.customStatement('UPDATE sync_meta SET applying = 0');
      }
      await _db.customStatement('DELETE FROM sync_dirty');
      await _db.customStatement('DELETE FROM sync_tombstones');
      await _db.customStatement('DELETE FROM sync_base');
      await _db.customStatement(
        'UPDATE sync_meta SET user_id = NULL, last_pull = NULL',
      );
    });
    _db.notifyUpdates({for (final t in syncTables) TableUpdate(t.name)});

    for (final path in paths) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- push

  Future<void> _push() async {
    for (final table in syncTables) {
      if (table.mergeable) {
        await _unlessOutdated(table.name, () => _mergeConcurrentEdits(table));
      }
      final keyMatch = table.keys.map((k) => "'$k', t.$k").join(', ');
      final rows = await _db
          .customSelect(
            'SELECT d.id AS _seq, '
            '${table.allColumns.map((c) => 't.$c').join(', ')} '
            'FROM sync_dirty d JOIN ${table.name} t '
            "ON d.row_key = json_object($keyMatch) "
            'WHERE d.table_name = ? ORDER BY d.id',
            variables: [Variable.withString(table.name)],
          )
          .get();
      await _unlessOutdated(table.name, () async {
        for (var i = 0; i < rows.length; i += _batchSize) {
          final batch = rows.skip(i).take(_batchSize).toList();
          await _remote.upsertRows(table.name, [
            for (final row in batch) _toRemote(row.data),
          ]);
          // By sequence id, so an edit made mid-push stays queued.
          for (final row in batch) {
            await _db.customStatement('DELETE FROM sync_dirty WHERE id = ?', [
              row.read<int>('_seq'),
            ]);
            if (table.mergeable) await _settleBase(table, row.data);
          }
        }
      });
    }

    // Deletes go children-first, mirroring how they were applied locally.
    final tombstones = await _db
        .customSelect(
          'SELECT table_name, row_key, deleted_at FROM sync_tombstones',
        )
        .get();
    final order = {for (final (i, t) in syncTables.indexed) t.name: i};
    final sorted = tombstones.toList()
      ..sort(
        (a, b) => order[b.read<String>('table_name')]!.compareTo(
          order[a.read<String>('table_name')]!,
        ),
      );
    for (final t in sorted) {
      final key = (jsonDecode(t.read<String>('row_key')) as Map)
          .cast<String, Object?>();
      await _unlessOutdated(t.read<String>('table_name'), () async {
        await _remote.markDeleted(
          t.read<String>('table_name'),
          key,
          _toIso(t.read<int>('deleted_at')),
        );
        // Only drop the tombstone we just sent; a re-created row's newer
        // state is handled by the row push above.
        await _db.customStatement(
          'DELETE FROM sync_tombstones WHERE table_name = ? AND row_key = ? '
          'AND deleted_at = ?',
          [
            t.read<String>('table_name'),
            t.read<String>('row_key'),
            t.read<int>('deleted_at'),
          ],
        );
      });
    }
  }

  /// Before pushing: for each locally edited row whose server copy also
  /// changed since this device last synced it, merge the two edits
  /// ([mergeRow]) into the local row, so the push carries both rather than
  /// one replacing the other. The merged row is stamped newer than the
  /// server's, so it wins the push.
  Future<void> _mergeConcurrentEdits(SyncTableSpec table) async {
    final pending = await _db
        .customSelect(
          'SELECT b.data FROM sync_base b JOIN sync_dirty d '
          'ON d.table_name = b.table_name AND d.row_key = b.row_key '
          'WHERE b.table_name = ?',
          variables: [Variable.withString(table.name)],
        )
        .get();
    if (pending.isEmpty) return;
    final bases = <String, Map<String, Object?>>{};
    for (final r in pending) {
      final base = (jsonDecode(r.read<String>('data')) as Map)
          .cast<String, Object?>();
      bases[base['id']! as String] = base;
    }

    var merged = false;
    for (final server in await _remote.fetchRows(
      table.name,
      bases.keys.toList(),
    )) {
      // A delete there vs an edit here stays last-write-wins.
      if (server['deleted_at'] != null) continue;
      final id = server['id']! as String;
      final base = bases[id];
      if (base == null) continue;
      final theirs = {
        for (final c in table.allColumns)
          c: syncDateTimeColumns.contains(c) && server[c] != null
              ? _fromIso(server[c]! as String)
              : server[c],
      };
      final changedThere = table.columns.any(
        (c) => c != 'updated_at' && theirs[c] != base[c],
      );
      if (!changedThere) continue;

      final local = await _db
          .customSelect(
            'SELECT ${table.allColumns.join(', ')} FROM ${table.name} '
            'WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull();
      if (local == null) continue;
      final mine = local.data;
      final result = mergeRow(
        table: table.name,
        columns: table.allColumns,
        base: base,
        local: mine,
        remote: theirs,
      );
      final mineAt = mine['updated_at']! as int;
      final theirsAt = theirs['updated_at']! as int;
      result['updated_at'] = mineAt > theirsAt ? mineAt : theirsAt + 1;

      await _db.transaction(() async {
        await _db.customStatement('UPDATE sync_meta SET applying = 1');
        try {
          await _db.customStatement(
            'UPDATE ${table.name} SET '
            '${table.columns.map((c) => '$c = ?').join(', ')} WHERE id = ?',
            [for (final c in table.columns) result[c], id],
          );
        } finally {
          await _db.customStatement('UPDATE sync_meta SET applying = 0');
        }
        // The server's version is what this device has now seen: if the
        // push fails, the next attempt merges against it, not the old base.
        await _db.customStatement(
          'UPDATE sync_base SET data = ? '
          "WHERE table_name = ? AND row_key = json_object('id', ?)",
          [jsonEncode(theirs), table.name, id],
        );
      });
      merged = true;
    }
    if (merged) _db.notifyUpdates({TableUpdate(table.name)});
  }

  /// After pushing [row]: the server now has it, so it's the base for any
  /// later merge. Usually nothing is left to merge and the base goes; if
  /// the row was edited again mid-push, the pushed version becomes its
  /// base.
  Future<void> _settleBase(
    SyncTableSpec table,
    Map<String, Object?> row,
  ) async {
    final id = row['id'];
    await _db.customStatement(
      'DELETE FROM sync_base '
      "WHERE table_name = ?1 AND row_key = json_object('id', ?2) "
      'AND NOT EXISTS (SELECT 1 FROM sync_dirty '
      "WHERE table_name = ?1 AND row_key = json_object('id', ?2))",
      [table.name, id],
    );
    await _db.customStatement(
      'UPDATE sync_base SET data = ? '
      "WHERE table_name = ? AND row_key = json_object('id', ?)",
      [
        jsonEncode({for (final c in table.allColumns) c: row[c]}),
        table.name,
        id,
      ],
    );
  }

  Map<String, Object?> _toRemote(Map<String, Object?> row) {
    return {
      for (final entry in row.entries)
        if (entry.key != '_seq')
          entry.key:
              syncDateTimeColumns.contains(entry.key) && entry.value != null
              ? _toIso(entry.value! as int)
              : entry.value,
      // Explicit null so re-linking a previously deleted join row revives it.
      'deleted_at': null,
    };
  }

  // ---------------------------------------------------------------- pull

  Future<void> _pull(Map<String, String> cursors) async {
    final newCursors = {...cursors};
    for (final table in syncTables) {
      if (_skipped.contains(table.name)) continue;
      final List<Map<String, Object?>> changes;
      try {
        changes = await _remote.fetchChanges(
          table.name,
          sinceIso: cursors[table.name],
        );
      } on SyncServerOutdated {
        _skipped.add(table.name);
        continue;
      }
      if (changes.isEmpty) continue;

      var wrote = false;
      var deleted = false;
      await _db.transaction(() async {
        await _db.customStatement('UPDATE sync_meta SET applying = 1');
        try {
          for (final row in changes) {
            switch (await _apply(table, row)) {
              case _Applied.written:
                wrote = true;
              case _Applied.deleted:
                deleted = true;
              case _Applied.none:
                break;
            }
          }
        } finally {
          await _db.customStatement('UPDATE sync_meta SET applying = 0');
        }
      });
      // Raw SQL bypasses drift's change tracking, so tell watching
      // queries (the notes list, etc.) to re-run.
      // A delete can cascade into any child table.
      if (deleted) {
        _db.notifyUpdates({for (final t in syncTables) TableUpdate(t.name)});
      } else if (wrote) {
        _db.notifyUpdates({TableUpdate(table.name)});
      }

      // The newest synced_at seen, computed rather than taken from the last
      // row so the cursor can't silently stall if the order is ever wrong.
      newCursors[table.name] = changes
          .map((r) => r['synced_at']! as String)
          .reduce(
            (a, b) => DateTime.parse(a).isAfter(DateTime.parse(b)) ? a : b,
          );
    }
    await _db.customStatement('UPDATE sync_meta SET last_pull = ?', [
      jsonEncode(newCursors),
    ]);
  }

  Future<_Applied> _apply(
    SyncTableSpec table,
    Map<String, Object?> remote,
  ) async {
    final where = table.keys.map((k) => '$k = ?').join(' AND ');
    final keyValues = [for (final k in table.keys) remote[k]];
    final remoteUpdated = _fromIso(remote['updated_at']! as String);

    final local = await _db
        .customSelect(
          'SELECT ${table.allColumns.join(', ')} FROM ${table.name} '
          'WHERE $where',
          variables: [for (final v in keyValues) Variable(v)],
        )
        .getSingleOrNull();
    if (local != null && local.read<int>('updated_at') > remoteUpdated) {
      return _Applied.none; // A newer local edit wins on the next push.
    }

    if (remote['deleted_at'] != null) {
      if (local == null) return _Applied.none;
      await _db.customStatement(
        'DELETE FROM ${table.name} WHERE $where',
        keyValues,
      );
      return _Applied.deleted;
    }

    final columns = table.allColumns;
    final values = [
      for (final c in columns)
        syncDateTimeColumns.contains(c) && remote[c] != null
            ? _fromIso(remote[c]! as String)
            : remote[c],
    ];
    // Pulls re-fetch the newest row at the cursor every time (the cursor is
    // inclusive). Skip rows that already match so that costs nothing and
    // doesn't wake watchers. Compared by content, not `updated_at`, because
    // that has one-second resolution and a same-second edit must still land.
    if (local != null &&
        [for (final c in columns) local.data[c]].indexed
            .every((e) => e.$2 == values[e.$1])) {
      return _Applied.none;
    }

    final updates = table.columns.map((c) => '$c = excluded.$c').join(', ');
    try {
      await _db.customStatement(
        'INSERT INTO ${table.name} (${columns.join(', ')}) '
        'VALUES (${List.filled(columns.length, '?').join(', ')}) '
        'ON CONFLICT (${table.keys.join(', ')}) DO UPDATE SET $updates',
        values,
      );
      return _Applied.written;
    } catch (e) {
      // A row whose parent was deleted (or never arrived) can't be stored.
      // Skip it rather than wedging sync; the delete already wins. Matched
      // on the message because the exception type differs depending on
      // whether drift runs the database in a background isolate.
      if (!e.toString().contains('FOREIGN KEY constraint failed')) rethrow;
      return _Applied.none;
    }
  }

  // ------------------------------------------------------------- helpers

  Future<_Meta> _readMeta() async {
    final row = await _db
        .customSelect('SELECT user_id, last_pull FROM sync_meta')
        .getSingle();
    final pull = row.read<String?>('last_pull');
    return _Meta(
      userId: row.read<String?>('user_id'),
      cursors: pull == null
          ? {}
          : (jsonDecode(pull) as Map).cast<String, String>(),
    );
  }

  static String _toIso(int seconds) => DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toIso8601String();

  static int _fromIso(String iso) =>
      DateTime.parse(iso).millisecondsSinceEpoch ~/ 1000;
}

enum _Applied { none, written, deleted }

class _Meta {
  const _Meta({required this.userId, required this.cursors});

  final String? userId;
  final Map<String, String> cursors;
}
