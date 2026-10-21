import 'dart:async';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/capture/quick_capture.dart';
import 'package:corplex/features/home/adaptive.dart';
import 'package:corplex/features/navigation/back_forward.dart';
import 'package:corplex/features/navigation/nav_history.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

class _Window implements MacWindow {
  final commands = StreamController<MenuCommand>.broadcast();
  final _full = ValueNotifier(false);
  final _band = ValueNotifier(macToolbarHeight);
  @override
  Stream<MenuCommand> get menuCommands => commands.stream;
  @override
  Stream<QuickCapture> get captures => const Stream.empty();
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async => enabled;
  @override
  ValueListenable<bool> get fullScreen => _full;
  @override
  ValueListenable<double> get titleBand => _band;
  @override
  Future<void> setToolbar(bool visible) async {}
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late AppDatabase db;
  late _Window window;
  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    window = _Window();
    for (final (id, title) in [
      ('n1', 'First note'),
      ('n2', 'Second note'),
      ('n3', 'Third note'),
    ]) {
      await db
          .into(db.notes)
          .insert(NotesCompanion.insert(id: Value(id), title: Value(title)));
    }
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    window.commands.close();
    db.close();
  });

  Future<ProviderContainer> show(WidgetTester tester) async {
    useMacWindow(tester, const Size(1728, 1080));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
          macWindowProvider.overrideWithValue(window),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(CorplexApp)));
  }

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, MenuCommand c) async {
    window.commands.add(c);
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Back and Forward replay through the real openers', (
    tester,
  ) async {
    final c = await show(tester);
    // No history yet: no buttons.
    expect(find.byKey(const ValueKey('nav-back')), findsNothing);
    await open(tester, 'First note');
    await open(tester, 'Second note');
    await open(tester, 'Third note');
    final history = c.read(navHistoryProvider.notifier).history;
    expect(history.entries.map((e) => e.target.key), [
      'note:n1',
      'note:n2',
      'note:n3',
    ]);
    expect(find.byKey(const ValueKey('nav-back')), findsOneWidget);

    await send(tester, MenuCommand.back);
    expect(c.read(selectedNoteProvider), 'n2');
    // Replaying did not record anything or leave the flag up.
    expect(history.entries, hasLength(3));
    expect(history.index, 1);
    expect(c.read(navReplayingProvider), isFalse);

    await tester.tap(find.byKey(const ValueKey('nav-back')));
    await tester.pumpAndSettle();
    expect(c.read(selectedNoteProvider), 'n1');
    expect(history.canGoBack, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('nav-back')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await send(tester, MenuCommand.forward);
    expect(c.read(selectedNoteProvider), 'n2');
    await tester.tap(find.byKey(const ValueKey('nav-forward')));
    await tester.pumpAndSettle();
    expect(c.read(selectedNoteProvider), 'n3');
    expect(history.canGoForward, isFalse);

    // A new visit from the middle drops what was ahead.
    await send(tester, MenuCommand.back);
    await open(tester, 'First note');
    expect(history.entries.map((e) => e.target.key), [
      'note:n1',
      'note:n2',
      'note:n1',
    ]);
    await teardown(tester);
  }, variant: macOnly);

  testWidgets('deleted places are forgotten, not replayed', (tester) async {
    final c = await show(tester);
    await open(tester, 'First note');
    await open(tester, 'Second note');
    await open(tester, 'Third note');
    await (db.delete(db.notes)..where((n) => n.id.equals('n2'))).go();
    await tester.pumpAndSettle();
    await send(tester, MenuCommand.back);
    // n2 is gone: back lands on n1.
    expect(c.read(selectedNoteProvider), 'n1');
    final history = c.read(navHistoryProvider.notifier).history;
    expect(history.entries.map((e) => e.target.key), ['note:n1', 'note:n3']);
    await send(tester, MenuCommand.forward);
    expect(c.read(selectedNoteProvider), 'n3');

    // Everything behind is gone: back does nothing.
    await (db.delete(db.notes)..where((n) => n.id.equals('n1'))).go();
    await tester.pumpAndSettle();
    await send(tester, MenuCommand.back);
    expect(c.read(selectedNoteProvider), 'n3');
    expect(history.entries.map((e) => e.target.key), ['note:n3']);
    await teardown(tester);
  }, variant: macOnly);

  testWidgets('a page pushed over home is closed before history walks', (
    tester,
  ) async {
    final c = await show(tester);
    await open(tester, 'First note');
    await open(tester, 'Second note');
    await send(tester, MenuCommand.trash);
    expect(find.byType(BackButton), findsOneWidget);
    await send(tester, MenuCommand.back);
    expect(find.byType(BackButton), findsNothing);
    // The route closed; history did not move.
    expect(c.read(selectedNoteProvider), 'n2');
    expect(c.read(navHistoryProvider.notifier).history.index, 1);
    await send(tester, MenuCommand.back);
    expect(c.read(selectedNoteProvider), 'n1');
    await teardown(tester);
  }, variant: macOnly);

  testWidgets('replaying an entry asks the screen to restore its scroll', (
    tester,
  ) async {
    final c = await show(tester);
    await open(tester, 'First note');
    await open(tester, 'Second note');
    final n = c.read(navHistoryProvider.notifier);
    n.reportScrollFor('note:n1', 0.4);
    expect(n.history.entries.first.scroll, 0.4);
    final seen = <NavScrollRequest?>[];
    c.listen(navScrollRequestProvider, (_, r) => seen.add(r));
    await send(tester, MenuCommand.back);
    expect(seen, contains((key: 'note:n1', fraction: 0.4)));
    expect(c.read(selectedNoteProvider), 'n1');
    await teardown(tester);
  }, variant: macOnly);

  testWidgets('restoreScrollFraction scrolls once the list has laid out', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: controller,
          children: [for (var i = 0; i < 100; i++) Text('row $i')],
        ),
      ),
    );
    expect(scrollFractionOf(controller), 0);
    restoreScrollFraction(controller, 0.5, () => true);
    await tester.pump();
    await tester.pump();
    final p = controller.position;
    expect(p.pixels, closeTo(p.maxScrollExtent / 2, 1));
    expect(scrollFractionOf(controller), closeTo(0.5, 0.01));
  });
}

