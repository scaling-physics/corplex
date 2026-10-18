import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_highlight.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

Widget _app(AppDatabase db) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    audioEngineProvider.overrideWithValue(FakeAudioEngine()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: const [
      FlutterQuillLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const NoteEditorScreen(noteId: 'n'),
  ),
);

void main() {
  late AppDatabase db;
  setUpAll(loadMacFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db.into(db.notes).insert(NotesCompanion.insert(id: const Value('n')));
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<QuillController> open(WidgetTester tester) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    final c = editor.controller;
    editor.focusNode.requestFocus();
    await tester.pump();
    c.replaceText(0, 0, 'hello', const TextSelection.collapsed(offset: 5));
    c.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      ChangeSource.local,
    );
    await tester.pump();
    return c;
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Highlight and Monospaced commands toggle on the selection', (
    tester,
  ) async {
    final c = await open(tester);
    Object? attr(String k) => c.getSelectionStyle().attributes[k]?.value;

    expect(dispatchMenuCommand(MenuCommand.highlight), isTrue);
    await tester.pump();
    expect(attr('background'), NoteHighlight.yellow.hex);
    expect(dispatchMenuCommand(MenuCommand.highlight), isTrue);
    await tester.pump();
    expect(attr('background'), isNull);

    expect(dispatchMenuCommand(MenuCommand.monospaced), isTrue);
    await tester.pump();
    expect(attr('code-block'), isTrue);
    expect(dispatchMenuCommand(MenuCommand.monospaced), isTrue);
    await tester.pump();
    expect(attr('code-block'), isNull);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('Shift+Cmd+E and Shift+Cmd+M reach the editor commands', (
    tester,
  ) async {
    final c = await open(tester);
    Object? attr(String k) => c.getSelectionStyle().attributes[k]?.value;
    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    await chord(LogicalKeyboardKey.keyE);
    expect(attr('background'), isNotNull);
    await chord(LogicalKeyboardKey.keyM);
    expect(attr('code-block'), isTrue);
    await dispose(tester);
  }, variant: macOnly);

  testWidgets('the format bar offers a colour menu', (tester) async {
    final c = await open(tester);
    await tester.tap(find.byTooltip('Highlight ⇧⌘E'));
    await tester.pumpAndSettle();
    expect(find.text('Pink'), findsOneWidget);
    await tester.tap(find.text('Pink'));
    await tester.pumpAndSettle();
    expect(
      c.getSelectionStyle().attributes['background']?.value,
      NoteHighlight.pink.hex,
    );
    await dispose(tester);
  }, variant: macOnly);
}
