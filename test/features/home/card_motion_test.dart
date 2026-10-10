import 'package:animations/animations.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:corplex/theme/motion_widgets.dart';
import 'package:corplex/theme/swipe_to_trash.dart';

import '../../support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];

  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();

  @override
  Future<void> reset() async {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('First note'),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> show(WidgetTester tester, Size logical) async {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(_NoShares()),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('phone: a note card grows into the editor and back', (
    tester,
  ) async {
    await show(tester, const Size(390, 844));
    expect(find.byType(OpenContainer<void>), findsOneWidget);

    await tester.tap(find.text('First note'));
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-transform the page is on its way in.
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.text('First note'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('iOS: a card pushes a normal page, so swipe-back still works', (
    tester,
  ) async {
    await show(tester, const Size(390, 844));
    expect(find.byType(OpenContainer<void>), findsNothing);

    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    await tester.dragFrom(const Offset(4, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.text('First note'), findsOneWidget);
    await dispose(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('tablet portrait still opens a page and returns', (tester) async {
    await show(tester, const Size(834, 1194));
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
    await dispose(tester);
  });

  testWidgets('wide: a card fills the pane, no container transform', (
    tester,
  ) async {
    await show(tester, const Size(1200, 800));
    expect(find.byType(OpenContainer<void>), findsNothing);
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();
    final editor = tester.widget<NoteEditorScreen>(
      find.byType(NoteEditorScreen),
    );
    expect(editor.embedded, isTrue);
    await dispose(tester);
  });

  testWidgets('swipe: the haptic fires once per crossing of the threshold', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester, const Size(390, 844));

    final width = tester.getSize(find.byType(SwipeToTrash)).width;
    final past = width * SwipeToTrash.threshold + 60;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First note')),
    );
    // The first move only starts the drag.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(Offset(past / 2, 0));
    await tester.pump();
    expect(haptics, isEmpty);
    await gesture.moveBy(Offset(past / 2, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.mediumImpact']);

    // Back below the threshold and across it again: a second tick.
    await gesture.moveBy(Offset(-past / 2, 0));
    await tester.pump();
    await gesture.moveBy(Offset(past / 2, 0));
    await tester.pump();
    expect(haptics, hasLength(2));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('First note'), findsNothing);
    await dispose(tester);
  });

  group('ListItemMotion', () {
    Widget harness(List<String> ids, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: NewItemScope(
            ids: ids,
            child: ListView(
              children: [
                for (var i = 0; i < ids.length; i++)
                  ListItemMotion(
                    key: ValueKey(ids[i]),
                    id: ids[i],
                    index: i,
                    child: SizedBox(height: 100, child: Text(ids[i])),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('items there from the start do not unfold; later ones do', (
      tester,
    ) async {
      await tester.pumpWidget(harness(['a']));
      expect(find.byType(SizeTransition), findsNothing);
      await tester.pumpAndSettle();

      await tester.pumpWidget(harness(['a', 'b']));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = tester.getSize(find.byType(SizeTransition)).height;
      expect(mid, inInclusiveRange(1, 99));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SizeTransition)).height, 100);
      expect(find.text('b'), findsOneWidget);

      // A rebuild with the same ids does nothing more.
      await tester.pumpWidget(harness(['a', 'b']));
      expect(tester.getSize(find.text('b')).height, 100);
    });

    testWidgets('reduced motion: new items are simply there', (tester) async {
      await tester.pumpWidget(harness(['a'], reduced: true));
      await tester.pumpWidget(harness(['a', 'b'], reduced: true));
      await tester.pump();
      expect(tester.getSize(find.byType(SizeTransition)).height, 100);
    });
  });

  testWidgets('a note added after the list is shown unfolds in place', (
    tester,
  ) async {
    await show(tester, const Size(390, 844));
    await tester.runAsync(
      () => db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n2'),
              title: const Value('Restored note'),
            ),
          ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Restored note'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Restored note'), findsOneWidget);
    await dispose(tester);
  });
}
