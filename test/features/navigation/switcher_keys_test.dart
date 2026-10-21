import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/navigation/quick_switcher_nav.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

final _body = jsonEncode([
  {'insert': 'Intro'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'text one\n'},
  {'insert': 'Methods'},
  {
    'insert': '\n',
    'attributes': {'header': 2},
  },
  {
    'insert': 'see paper',
    'attributes': {'link': 'corplex://paper/zzz?page=2'},
  },
  {'insert': '\nplain words\n'},
]);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(loadMacFonts);
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Chapter'),
            content: Value(_body),
          ),
        );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      ],
    );
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    container.dispose();
    await db.close();
  });

  Future<QuillController> open(WidgetTester tester) async {
    useMacWindow(tester, const Size(1280, 800));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: NoteEditorScreen(noteId: 'n')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = true,
    bool alt = false,
    bool shift = false,
  }) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('the editor registers itself for the switcher', (tester) async {
    await open(tester);
    final nav = container.read(noteNavigatorRegistryProvider).focused;
    expect(nav, isNotNull);
    expect(nav!.noteId, 'n');
    expect([for (final h in nav.headings()) h.text], ['Intro', 'Methods']);
    nav.jumpTo(nav.headings().last);
    await tester.pumpAndSettle();
    final c = tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    expect(c.selection.baseOffset, nav.headings().last.offset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(noteNavigatorRegistryProvider).focused, isNull);
  }, variant: macOnly);

  testWidgets('⌥⌘↑ / ⌥⌘↓ move between headings', (tester) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    final methods = _body.contains('Methods') ? 15 : 0;
    await chord(tester, LogicalKeyboardKey.arrowDown, alt: true);
    expect(c.selection.baseOffset, methods);
    // No further heading: stays.
    await chord(tester, LogicalKeyboardKey.arrowDown, alt: true);
    expect(c.selection.baseOffset, methods);
    await chord(tester, LogicalKeyboardKey.arrowUp, alt: true);
    expect(c.selection.baseOffset, 0);
  }, variant: macOnly);

  testWidgets('⌘L follows the link under the caret', (tester) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 26),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyL);
    // The paper isn't there: the editor says so, as a tap on the link would.
    expect(find.text('That paper was removed.'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('⌘L with no link says so', (tester) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    await chord(tester, LogicalKeyboardKey.keyL);
    expect(find.text('No link at the cursor.'), findsOneWidget);
  }, variant: macOnly);

  testWidgets('⇧⌘O asks for the switcher exactly once', (tester) async {
    await open(tester);
    expect(container.read(quickSwitcherRequestProvider), 0);
    await chord(tester, LogicalKeyboardKey.keyO, shift: true);
    expect(container.read(quickSwitcherRequestProvider), 1);
  }, variant: macOnly);

  testWidgets('menu commands reach the focused editor first, once', (
    tester,
  ) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    expect(dispatchMenuCommand(MenuCommand.nextHeading), isTrue);
    await tester.pumpAndSettle();
    expect(c.selection.baseOffset, 15);
    expect(dispatchMenuCommand(MenuCommand.goTo), isTrue);
    expect(container.read(quickSwitcherRequestProvider), 1);
  }, variant: macOnly);
}
