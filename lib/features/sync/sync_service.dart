import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';

enum SyncStatus { offline, syncing, upToDate, error }

/// What the rest of the app knows about sync: start/stop it for a signed-in
/// user, ask for a sync, and observe its status. Screens depend only on
/// this interface, never on the backend behind it.
abstract class SyncService {
  Stream<SyncStatus> get statusChanges;

  SyncStatus get currentStatus;

  /// Human-readable reason for the last failure, when [currentStatus] is
  /// [SyncStatus.error].
  String? get lastError;

  /// Starts syncing for the given signed-in user: an immediate sync, then
  /// again shortly after local changes and on a slow timer.
  Future<void> start({required String userId});

  /// True when this device holds another account's data, so syncing is
  /// blocked until [eraseLocalData] is called.
  bool get accountMismatch;

  /// Changes that exist only on this device (unpushed edits/deletes, files
  /// not yet uploaded) and would be lost by [eraseLocalData].
  Future<int> pendingChanges();

  /// Wipes all local data and files, then re-syncs if a user is signed in.
  Future<void> eraseLocalData();

  /// Runs a sync now. A no-op when not started or one is already running.
  Future<void> syncNow();

  Future<void> stop();
}

/// Used when no backend is configured: reports the app as permanently
/// offline, so the UI can show accurate status without pretending to sync.
class NoOpSyncService implements SyncService {
  @override
  Stream<SyncStatus> get statusChanges => const Stream.empty();

  @override
  SyncStatus get currentStatus => SyncStatus.offline;

  @override
  String? get lastError => null;

  @override
  bool get accountMismatch => false;

  @override
  Future<int> pendingChanges() async => 0;

  @override
  Future<void> eraseLocalData() async {}

  @override
  Future<void> start({required String userId}) async {}

  @override
  Future<void> syncNow() async {}

  @override
  Future<void> stop() async {}
}

/// Drives a [SyncEngine]: syncs on start, a few seconds after any local
/// write (debounced), and periodically to pick up other devices' changes.
/// Failures (offline, server down) just set [SyncStatus.error]; local data
/// is never affected and the next trigger retries.
class EngineSyncService implements SyncService {
  EngineSyncService(
    this._db,
    this._engine, {
    this.debounce = const Duration(seconds: 5),
    this.pollInterval = const Duration(minutes: 5),
  });

  final AppDatabase _db;
  final SyncEngine _engine;
  final Duration debounce;
  final Duration pollInterval;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus _current = SyncStatus.offline;
  String? _lastError;
  bool _accountMismatch = false;
  String? _userId;
  bool _running = false;

  StreamSubscription<Object?>? _localChanges;
  Timer? _debounceTimer;
  Timer? _pollTimer;

  @override
  Stream<SyncStatus> get statusChanges => _status.stream;

  @override
  SyncStatus get currentStatus => _current;

  @override
  String? get lastError => _lastError;

  @override
  bool get accountMismatch => _accountMismatch;

  @override
  Future<int> pendingChanges() => _engine.pendingChanges();

  @override
  Future<void> eraseLocalData() async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _running = true; // Keep scheduled syncs out while wiping.
    try {
      await _engine.eraseLocalData();
      _accountMismatch = false;
      _lastError = null;
    } finally {
      _running = false;
    }
    if (_userId != null) await syncNow();
  }

  @override
  Future<void> start({required String userId}) async {
    if (_userId == userId) return;
    await stop();
    _userId = userId;
    _localChanges = _db.tableUpdates().listen((_) {
      if (_running) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounce, () async {
        // Pulled rows and downloaded files also raise table updates. Only
        // sync for a genuine local change, or those would retrigger us.
        if (await _engine.pendingChanges() > 0) await syncNow();
      });
    });
    _pollTimer = Timer.periodic(pollInterval, (_) => syncNow());
    await syncNow();
  }

  @override
  Future<void> syncNow() async {
    final userId = _userId;
    if (userId == null || _running) return;
    _running = true;
    _emit(SyncStatus.syncing);
    try {
      await _engine.sync(userId: userId);
      _lastError = null;
      _accountMismatch = false;
      _emit(SyncStatus.upToDate);
    } catch (e) {
      _accountMismatch = e is SyncAccountMismatch;
      _lastError =
          e is SyncAccountMismatch ||
              e is SyncFilesIncomplete ||
              e is SyncServerOutdated
          ? e.toString()
          : 'Couldn\'t sync. Your notes are safe on this device.';
      _emit(SyncStatus.error);
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> stop() async {
    _userId = null;
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    await _localChanges?.cancel();
    _localChanges = null;
    _lastError = null;
    _accountMismatch = false;
    _emit(SyncStatus.offline);
  }

  void _emit(SyncStatus status) {
    _current = status;
    if (!_status.isClosed) _status.add(status);
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => NoOpSyncService());

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service.statusChanges;
});
