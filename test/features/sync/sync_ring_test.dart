import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/sync/sync_ring.dart';
import 'package:corplex/features/sync/sync_service.dart';

class _FakeSync extends NoOpSyncService {
  final controller = StreamController<SyncStatus>.broadcast();
  SyncStatus status = SyncStatus.offline;

  void set(SyncStatus s) {
    status = s;
    controller.add(s);
  }

  @override
  Stream<SyncStatus> get statusChanges => controller.stream;

  @override
  SyncStatus get currentStatus => status;
}

Widget _host(SyncService sync, {bool reduced = false}) => ProviderScope(
  overrides: [syncServiceProvider.overrideWithValue(sync)],
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: SyncRing(child: Icon(Icons.person))),
      ),
    ),
  ),
);

void main() {
  final ring = find.byKey(const ValueKey('sync-ring'));

  testWidgets('the ring shows only while a sync runs', (tester) async {
    final sync = _FakeSync();
    addTearDown(sync.controller.close);
    await tester.pumpWidget(_host(sync));
    await tester.pumpAndSettle();
    expect(ring, findsNothing);

    sync.set(SyncStatus.syncing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ring, findsOneWidget);
    expect(
      find.descendant(of: ring, matching: find.byType(RotationTransition)),
      findsOneWidget,
    );

    sync.set(SyncStatus.upToDate);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(ring, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion holds the ring still', (tester) async {
    final sync = _FakeSync()..status = SyncStatus.syncing;
    addTearDown(sync.controller.close);
    await tester.pumpWidget(_host(sync, reduced: true));
    await tester.pumpAndSettle(); // Would time out if it spun.
    expect(ring, findsOneWidget);
  });

  testWidgets('with no sync backend nothing ever shows', (tester) async {
    await tester.pumpWidget(_host(NoOpSyncService()));
    await tester.pumpAndSettle();
    expect(ring, findsNothing);
  });
}
