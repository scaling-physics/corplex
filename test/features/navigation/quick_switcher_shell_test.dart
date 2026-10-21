import 'dart:async';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/home/adaptive.dart';
import 'package:corplex/features/navigation/quick_switcher_nav.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/share/share_import.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

import 'package:corplex/features/capture/quick_capture.dart';

class _Window implements MacWindow {
  final commands = StreamController<MenuCommand>.broadcast();
  @override
  Stream<QuickCapture> get captures => const Stream.empty();
  @override
  Future<bool> setQuickNoteHotKey(bool enabled) async => false;
  final _full = ValueNotifier(false);
  @override
  Stream<MenuCommand> get menuCommands => commands.stream;
  @override
  ValueListenable<bool> get fullScreen => _full;
  final _band = ValueNotifier(macToolbarHeight);
  @override
  ValueListenable<double> get titleBand => _band;
  @override
  Future<void> setToolbar(bool visible) async {}
  @override
  Future<void> startDrag() async {}
  @override
  Future<void> zoom() async {}
  @override
  Future<bool> printPdf(Uint8List pdf, String title) async => true;
}

void main() {
  late AppDatabase db;
  late _Window window;
  late List<Object> overrides;
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(CorplexApp)));

  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    window = _Window();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Replay notes'),
          ),
        );
    overrides = [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      shareIntentSourceProvider.overrideWithValue(const NoShareIntentSource()),
      macWindowProvider.overrideWithValue(window),
    ];
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await window.commands.close();
    await db.close();
  });

  Future<void> show(WidgetTester tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await tester.pumpWidget(
      ProviderScope(overrides: overrides.cast(), child: const CorplexApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'Go to… from the menu opens the switcher; choosing a note opens it',
    (tester) async {
      await show(tester);
      window.commands.add(MenuCommand.goTo);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('switcher-field')),
        'replay',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
      expect(container(tester).read(selectedNoteProvider), 'n1');
      await dispose(tester);
    },
    variant: macOnly,
  );

  testWidgets('a second request while open does not stack a second switcher', (
    tester,
  ) async {
    await show(tester);
    window.commands.add(MenuCommand.goTo);
    await tester.pumpAndSettle();
    container(tester).read(quickSwitcherRequestProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('a command from > runs through the menu path', (tester) async {
    await show(tester);
    window.commands.add(MenuCommand.goTo);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('switcher-field')),
      '>trash',
    );
    await tester.pumpAndSettle();
    // No trash command is listed: nothing to run.
    expect(find.textContaining('Nothing matches'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('switcher-field')),
      '>shortcuts',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyboard-shortcuts')), findsOneWidget);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('Ctrl+K opens it without the Mac menu (iPad/Android keyboards)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(overrides: overrides.cast(), child: const CorplexApp()),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('on a Mac the shell leaves ⌘K to the menu (no double open)', (
    tester,
  ) async {
    await show(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-switcher')), findsNothing);
    await dispose(tester);
  }, variant: macOnly);
}
