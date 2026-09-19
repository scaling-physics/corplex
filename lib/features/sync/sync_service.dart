import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncStatus { offline, syncing, upToDate, error }

/// Abstraction over "push/pull local changes to the sync backend", so the
/// real implementation (PowerSync, connected to a Supabase Postgres
/// database) can be dropped in later without the rest of the app knowing
/// or caring — screens only ever depend on this interface.
abstract class SyncService {
  Stream<SyncStatus> get statusChanges;

  SyncStatus get currentStatus;

  /// Starts syncing for the given signed-in user. A no-op until a real
  /// backend is wired up.
  Future<void> start({required String userId});

  Future<void> stop();
}

/// Default implementation while there's no PowerSync/Supabase project
/// configured yet: reports the app as permanently offline, so the UI can
/// show accurate status without pretending to sync.
class NoOpSyncService implements SyncService {
  @override
  Stream<SyncStatus> get statusChanges => const Stream.empty();

  @override
  SyncStatus get currentStatus => SyncStatus.offline;

  @override
  Future<void> start({required String userId}) async {}

  @override
  Future<void> stop() async {}
}

final syncServiceProvider = Provider<SyncService>((ref) => NoOpSyncService());
