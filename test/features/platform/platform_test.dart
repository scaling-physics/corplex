import 'dart:async';

import 'package:animations/animations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/open_card.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/quick_action_source.dart';
import 'package:corplex/features/platform/widget_data.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';

class _NoShares implements ShareIntentSource {
  @override
  Future<List<SharedMediaFile>> initial() async => const [];
  @override
  Stream<List<SharedMediaFile>> get stream => const Stream.empty();
  @override
  Future<void> reset() async {}
}

class _FakeQuick implements QuickActionSource {
  _FakeQuick(this.launch);
  final String? launch;
  void Function(String)? handler;

  @override
  Future<void> start(void Function(String type) onAction) async {
    handler = onAction;
    if (launch != null) onAction(launch!);
  }
}

class _FakeBridge implements HomeWidgetBridge {
  _FakeBridge({this.launch});
  final Uri? launch;
  final published = <WidgetPayload>[];
  final controller = StreamController<Uri?>.broadcast();

  @override
  Future<void> publish(WidgetPayload payload) async => published.add(payload);
  @override
  Future<Uri?> initialLaunch() async => launch;
  @override
  Stream<Uri?> get clicks => controller.stream;
}

Paper _paper(
  String id, {
  ReadingStatus? status,
  int? page,
  required int minute,
  String? pdf,
}) => Paper(
  id: id,
  title: 'Paper $id',
  authors: '',
  readingStatus: status,
  lastPage: page,
  pdfPath: pdf,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026, 1, 1, 0, minute),
);

void main() {
  group('widget data', () {
    test('prefers the most recent paper being read', () {
      final picked = pickContinueReading([
        _paper('a', status: ReadingStatus.reading, page: 3, minute: 1),
        _paper('b', status: ReadingStatus.reading, page: 9, minute: 5),
        _paper('c', status: ReadingStatus.done, page: 2, minute: 30),
      ]);
      expect(picked!.id, 'b');
    });

    test('falls back to the newest paper with a remembered page', () {
      final picked = pickContinueReading([
        _paper('a', page: 3, minute: 1),
        _paper('b', minute: 50),
        _paper('c', page: 7, minute: 9),
      ]);
      expect(picked!.id, 'c');
      expect(pickContinueReading([_paper('b', minute: 50)]), isNull);
    });

    test('payload carries title, page and a paper link', () {
      final p = widgetPayloadFor(_paper('x', page: 12, minute: 1));
      expect(p.title, 'Paper x');
      expect(p.detail, 'p. 12');
      expect(p.uri, 'corplex://paper/x?page=12');
      expect(widgetPayloadFor(null).title, isNull);
    });
  });

  group('in the app', () {
    late AppDatabase db;

    setUp(() {
      EditableText.debugDeterministicCursor = true;
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() {
      EditableText.debugDeterministicCursor = false;
      db.close();
    });

    Future<void> pumpApp(
      WidgetTester tester, {
      _FakeQuick? quick,
      _FakeBridge? bridge,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            shareIntentSourceProvider.overrideWithValue(_NoShares()),
            quickActionSourceProvider.overrideWithValue(
              quick ?? _FakeQuick(null),
            ),
            homeWidgetBridgeProvider.overrideWithValue(bridge ?? _FakeBridge()),
            widgetDebounceProvider.overrideWithValue(Duration.zero),
          ],
          child: const CorplexApp(),
        ),
      );
    }

    /// Database work runs on real time, so alternate frames with real waits.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('launch quick action opens a new note', (tester) async {
      await pumpApp(tester, quick: _FakeQuick(quickNewNote));
      await settle(tester);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(await db.select(db.notes).get(), hasLength(1));
      await dispose(tester);
    });

    testWidgets('quick action while running opens a new note', (tester) async {
      final quick = _FakeQuick(null);
      await pumpApp(tester, quick: quick);
      await tester.pump();
      expect(find.byType(NoteEditorScreen), findsNothing);
      quick.handler!(quickNewNote);
      await settle(tester);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('widget tap on "new note" link opens a new note', (
      tester,
    ) async {
      await pumpApp(tester, bridge: _FakeBridge(launch: newNoteUri));
      await settle(tester);
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('widget tap on a paper without a local PDF opens its screen', (
      tester,
    ) async {
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p1'), title: 'Attn'));
      final bridge = _FakeBridge();
      await pumpApp(tester, bridge: bridge);
      await tester.pump();
      bridge.controller.add(Uri.parse('corplex://paper/p1?page=4'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Attn'), findsWidgets);
      expect(find.byType(BackButton), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('publishes the continue-reading paper, then updates it', (
      tester,
    ) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Attention',
              readingStatus: const Value(ReadingStatus.reading),
              lastPage: const Value(6),
            ),
          );
      final bridge = _FakeBridge();
      await pumpApp(tester, bridge: bridge);
      await settle(tester);
      expect(bridge.published.last.title, 'Attention');
      expect(bridge.published.last.detail, 'p. 6');

      await (db.update(db.papers)..where((p) => p.id.equals('p1'))).write(
        const PapersCompanion(lastPage: Value(8)),
      );
      await settle(tester);
      expect(bridge.published.last.detail, 'p. 8');
      await dispose(tester);
    });
  });

  group('OpenCard hover', () {
    double elevationOf(WidgetTester tester) {
      final container = find.byType(OpenContainer<void>);
      if (container.evaluate().isNotEmpty) {
        return tester.widget<OpenContainer<void>>(container).closedElevation;
      }
      return tester.widget<Card>(find.byType(Card)).elevation!;
    }

    Future<void> pumpCard(WidgetTester tester, TargetPlatform platform) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: platform,
            cardTheme: const CardThemeData(elevation: 0),
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 80,
                child: OpenCard(
                  selected: false,
                  onOpenInPane: () {},
                  pageBuilder: (_) => const Scaffold(),
                  child: const Text('card'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('a mouse lifts the card on $platform', (tester) async {
        await pumpCard(tester, platform);
        expect(elevationOf(tester), 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('card')));
        await tester.pumpAndSettle();
        expect(elevationOf(tester), OpenCard.hoverLift);
        await mouse.moveTo(const Offset(700, 500));
        await tester.pumpAndSettle();
        expect(elevationOf(tester), 0);
      });

      testWidgets('touch and pen do not lift it on $platform', (tester) async {
        await pumpCard(tester, platform);
        for (final kind in [
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        ]) {
          final g = await tester.createGesture(kind: kind);
          await g.addPointer(location: tester.getCenter(find.text('card')));
          await g.moveTo(
            tester.getCenter(find.text('card')) + const Offset(1, 1),
          );
          await tester.pumpAndSettle();
          expect(elevationOf(tester), 0);
          await g.removePointer();
        }
      });
    }
  });
}
