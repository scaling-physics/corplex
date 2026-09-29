import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/sync/sync_engine.dart';
import 'package:corplex/features/sync/sync_remote.dart';
import 'package:corplex/features/sync/sync_service.dart';

import '../../support/fake_sync_remote.dart';

class _FailingRemote extends FakeSyncRemote {
  @override
  Future<List<Map<String, Object?>>> fetchChanges(
    String table, {
    String? sinceIso,
  }) => throw Exception('offline');
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  EngineSyncService serviceFor(SyncRemote remote) => EngineSyncService(
    db,
    SyncEngine(db, remote),
    debounce: const Duration(milliseconds: 20),
    pollInterval: const Duration(hours: 1),
  );

  test('start syncs immediately and reports up to date', () async {
    final remote = FakeSyncRemote();
    await db.into(db.folders).insert(FoldersCompanion.insert(name: 'F'));
    final service = serviceFor(remote);

    await service.start(userId: 'u1');

    expect(service.currentStatus, SyncStatus.upToDate);
    expect(remote.tables['folders'], hasLength(1));
    await service.stop();
    expect(service.currentStatus, SyncStatus.offline);
  });

  test('a local write is pushed shortly afterwards', () async {
    final remote = FakeSyncRemote();
    final service = serviceFor(remote);
    await service.start(userId: 'u1');

    await db.into(db.tags).insert(TagsCompanion.insert(name: 'new'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(remote.tables['tags'], hasLength(1));
    await service.stop();
  });

  test('a failing server sets error status and keeps local data', () async {
    await db.into(db.folders).insert(FoldersCompanion.insert(name: 'F'));
    final service = serviceFor(_FailingRemote());

    await service.start(userId: 'u1');

    expect(service.currentStatus, SyncStatus.error);
    expect(service.lastError, contains('safe on this device'));
    expect(await db.select(db.folders).get(), hasLength(1));
    await service.stop();
  });
}
