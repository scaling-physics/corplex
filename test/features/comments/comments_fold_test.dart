import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/heading_fold.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

Delta sample() => Delta()
  ..insert('One')
  ..insert('\n', {'header': 1})
  ..insert('alpha\nbeta\n')
  ..insert('Sub')
  ..insert('\n', {'header': 2})
  ..insert('gamma\n')
  ..insert('Two')
  ..insert('\n', {'header': 1})
  ..insert('delta\n');

const whole = 'One\nalpha\nbeta\nSub\ngamma\nTwo\ndelta\n';
const folded = 'One\n￼\nTwo\ndelta\n';

void main() {
  late AppDatabase db;

  setUpAll(loadMacFonts);
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({
      'notes.folds.n': [foldFingerprint('n', 'One', 0)],
    });
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Chapter'),
            content: Value(jsonEncode(sample().toJson())),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pumpAndSettle();
  }

  QuillController controllerOf(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('a comment on a hidden passage is found, and picking opens it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await db
        .into(db.noteComments)
        .insert(
          NoteCommentsCompanion.insert(
            id: const Value('c1'),
            noteId: 'n',
            quote: const Value('gamma'),
            anchor: Value(whole.indexOf('gamma')),
            body: const Value('Explain gamma'),
          ),
        );
    await open(tester);
    final c = controllerOf(tester);
    expect(c.document.toPlainText(), folded);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('Explain gamma'), findsOneWidget);
    expect(find.text('Passage changed'), findsNothing);

    await tester.tap(find.text('Explain gamma'));
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), whole);
    expect(
      c.document.toPlainText().substring(c.selection.start, c.selection.end),
      'gamma',
    );
    await close(tester);
  });

  testWidgets('an anchor saved while folded is the whole note\'s offset', (
    tester,
  ) async {
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await open(tester);
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.focusNode.requestFocus();
    await tester.pump();
    final c = editor.controller;
    expect(c.document.toPlainText(), folded);
    final at = folded.indexOf('delta');
    c.updateSelection(
      TextSelection(baseOffset: at, extentOffset: at + 5),
      ChangeSource.local,
    );
    await tester.pump();
    expect(dispatchMenuCommand(MenuCommand.addComment), isTrue);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('comment-body')), 'Hm');
    await tester.tap(find.byKey(const ValueKey('comment-save')));
    await tester.pumpAndSettle();

    final rows = await db.select(db.noteComments).get();
    expect(rows.single.quote, 'delta');
    expect(rows.single.anchor, whole.indexOf('delta'));
    // Still folded: nothing was opened to do it.
    expect(c.document.toPlainText(), folded);
    await close(tester);
  }, variant: macOnly);
}
