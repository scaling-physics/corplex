import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/sync_schema.dart';

/// The server side of sync, as narrow as the engine needs so it can be
/// faked in tests. Rows use the remote column format: snake_case names
/// matching [SyncTableSpec], timestamps as ISO-8601 strings, plus the
/// server-managed `deleted_at` and `synced_at`.
///
/// Conflict rule (enforced by the server): a write whose `updated_at` is
/// older than the stored row's is silently ignored — last write wins.
abstract class SyncRemote {
  Future<void> upsertRows(String table, List<Map<String, Object?>> rows);

  /// Soft-deletes the row with the given primary key. Never inserts.
  Future<void> markDeleted(
    String table,
    Map<String, Object?> key,
    String deletedAtIso,
  );

  /// Rows changed at or after [sinceIso] (all rows when null), including
  /// soft-deleted ones, oldest `synced_at` first.
  Future<List<Map<String, Object?>>> fetchChanges(
    String table, {
    String? sinceIso,
  });
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  static const _pageSize = 500;

  @override
  Future<void> upsertRows(String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final spec = syncTables.firstWhere((t) => t.name == table);
    await _client.from(table).upsert(rows, onConflict: spec.keys.join(','));
  }

  @override
  Future<void> markDeleted(
    String table,
    Map<String, Object?> key,
    String deletedAtIso,
  ) async {
    await _client
        .from(table)
        .update({'deleted_at': deletedAtIso, 'updated_at': deletedAtIso})
        .match(key.cast<String, Object>())
        // Older than what the server holds means a newer edit exists.
        .lte('updated_at', deletedAtIso);
  }

  @override
  Future<List<Map<String, Object?>>> fetchChanges(
    String table, {
    String? sinceIso,
  }) async {
    final result = <Map<String, Object?>>[];
    final spec = syncTables.firstWhere((t) => t.name == table);
    for (var offset = 0; ; offset += _pageSize) {
      var query = _client.from(table).select();
      if (sinceIso != null) query = query.gte('synced_at', sinceIso);
      final page = await query
          .order('synced_at')
          .order(spec.keys.first)
          .range(offset, offset + _pageSize - 1);
      result.addAll(page.cast<Map<String, Object?>>());
      if (page.length < _pageSize) return result;
    }
  }
}
