import 'dart:io';
import 'dart:typed_data';

import 'package:corplex/features/sync/file_sync.dart';
import 'package:corplex/data/sync_schema.dart';
import 'package:corplex/features/sync/sync_remote.dart';

/// In-memory stand-in for the Supabase tables, reproducing the server-side
/// rules the engine relies on: last-write-wins on `updated_at`, server-set
/// `synced_at`, soft deletes.
class FakeSyncRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, Object?>>> tables = {};
  int _clock = 0;

  /// Tables this fake "server" hasn't been migrated to have: any call for
  /// them answers like PostgREST does for a missing table.
  final Set<String> missingTables = {};

  void _requireTable(String table) {
    if (missingTables.contains(table)) throw const SyncServerOutdated();
  }

  /// Return changes newest-first, like postgrest-dart's default order, to
  /// check the engine doesn't depend on the order it receives rows in.
  bool newestFirst = false;

  /// Strictly increasing so `synced_at` ordering is deterministic.
  String _nextSyncedAt() => DateTime.utc(
    2030,
    1,
    1,
  ).add(Duration(milliseconds: ++_clock)).toIso8601String();

  String _id(String table, Map<String, Object?> row) {
    final spec = syncTables.firstWhere((t) => t.name == table);
    return spec.keys.map((k) => row[k]).join('|');
  }

  Map<String, Map<String, Object?>> _table(String name) =>
      tables.putIfAbsent(name, () => {});

  @override
  Future<void> upsertRows(String table, List<Map<String, Object?>> rows) async {
    _requireTable(table);
    for (final row in rows) {
      final id = _id(table, row);
      final existing = _table(table)[id];
      if (existing != null &&
          DateTime.parse(row['updated_at']! as String)
              .isBefore(DateTime.parse(existing['updated_at']! as String))) {
        continue;
      }
      _table(table)[id] = {...row, 'synced_at': _nextSyncedAt()};
    }
  }

  @override
  Future<void> markDeleted(
    String table,
    Map<String, Object?> key,
    String deletedAtIso,
  ) async {
    _requireTable(table);
    final id = _id(table, key);
    final existing = _table(table)[id];
    if (existing == null) return;
    if (DateTime.parse(deletedAtIso)
        .isBefore(DateTime.parse(existing['updated_at']! as String))) {
      return;
    }
    _table(table)[id] = {
      ...existing,
      'deleted_at': deletedAtIso,
      'updated_at': deletedAtIso,
      'synced_at': _nextSyncedAt(),
    };
  }

  @override
  Future<List<Map<String, Object?>>> fetchRows(
    String table,
    List<String> ids,
  ) async {
    _requireTable(table);
    return [
      for (final id in ids)
        if (_table(table)[id] case final row?) {...row},
    ];
  }

  @override
  Future<Set<String>> liveStorageKeys() async => {
    for (final t in const ['papers', 'attachments'])
      for (final r in _table(t).values)
        if (r['storage_key'] != null && r['deleted_at'] == null)
          r['storage_key']! as String,
  };

  @override
  Future<List<Map<String, Object?>>> fetchChanges(
    String table, {
    String? sinceIso,
  }) async {
    _requireTable(table);
    final since = sinceIso == null ? null : DateTime.parse(sinceIso);
    final rows =
        _table(table).values.where((r) {
          return since == null ||
              !DateTime.parse(r['synced_at']! as String).isBefore(since);
        }).toList()..sort(
          (a, b) =>
              (a['synced_at']! as String).compareTo(b['synced_at']! as String),
        );
    return newestFirst ? rows.reversed.toList() : rows;
  }
}

/// In-memory stand-in for Supabase Storage.
class FakeFileRemote implements FileRemote {
  final Map<String, Uint8List> objects = {};
  final Map<String, DateTime> created = {};
  int uploads = 0;
  bool failing = false;

  @override
  Future<void> upload(String key, File file) async {
    if (failing) throw Exception('offline');
    uploads++;
    objects[key] = await file.readAsBytes();
    created[key] = DateTime.now();
  }

  @override
  Future<List<RemoteObject>> list(String prefix) async => [
    for (final k in objects.keys)
      if (k.startsWith('$prefix/')) RemoteObject(k, created[k]!),
  ];

  @override
  Future<void> remove(List<String> keys) async {
    for (final k in keys) {
      objects.remove(k);
      created.remove(k);
    }
  }

  @override
  Future<Uint8List> download(String key) async {
    if (failing) throw Exception('offline');
    return objects[key]!;
  }
}
