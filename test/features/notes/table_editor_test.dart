import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_stats.dart';
import 'package:corplex/features/notes/note_table.dart';
import 'package:corplex/features/notes/table_embed.dart';
import 'package:corplex/features/platform/mac_window.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

String _c(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  late AppDatabase db;

  setUp(() {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> addNote(String id, String content) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value('Note $id'),
          content: Value(content),
        ),
      );

  Future<QuillController> open(WidgetTester tester, String noteId) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: NoteEditorScreen(noteId: noteId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> slash(WidgetTester tester, QuillController c, String cmd) async {
    c.replaceText(
      c.selection.baseOffset,
      0,
      '/',
      TextSelection.collapsed(offset: c.selection.baseOffset + 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(cmd));
    await tester.pumpAndSettle();
  }

  List<NoteTable> tables(QuillController c) => [
    for (final o in c.document.toDelta().toJson())
      if (o['insert'] is Map && (o['insert'] as Map).containsKey('table'))
        NoteTable.decode((o['insert'] as Map)['table'] as String),
  ];

  Finder cell(int r, int c) => find.byKey(ValueKey('table-cell-$r-$c'));

  Future<void> type(WidgetTester tester, int r, int c, String text) async {
    await tester.enterText(cell(r, c), text);
    await tester.pump();
  }

  Future<void> settleWrites(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  Future<QuillController> withTable(WidgetTester tester) async {
    await addNote('n1', _c(''));
    final c = await open(tester, 'n1');
    await slash(tester, c, 'Table');
    return c;
  }

  testWidgets('/ Table inserts a 3x3 table on its own line', (tester) async {
    await addNote('n1', _c('before after'));
    final c = await open(tester, 'n1');
    c.updateSelection(
      const TextSelection.collapsed(offset: 7),
      ChangeSource.local,
    );
    await tester.pump();
    await slash(tester, c, 'Table');
    final t = tables(c).single;
    expect(t.rows, hasLength(3));
    expect(t.columns, 3);
    expect(t.header, isTrue);
    // The text around it stays on lines of its own.
    final lines = c.document.toPlainText().split('\n');
    expect(lines.where((l) => l.contains('￼')).single, '￼');
    expect(lines.any((l) => l.startsWith('before')), isTrue);
    expect(find.byKey(const ValueKey('table-grid')), findsOneWidget);
    // The first cell is ready to type in.
    final field = tester.widget<TextField>(cell(0, 0));
    expect(field.focusNode!.hasFocus, isTrue);
    await close(tester);
  });

  testWidgets('typing in a cell writes the embed', (tester) async {
    final c = await withTable(tester);
    await type(tester, 1, 2, 'hello');
    await settleWrites(tester);
    expect(tables(c).single.rows[1][2], 'hello');
    expect(find.text('hello'), findsOneWidget);
    // Still the same field, still holding its text.
    expect(tester.widget<TextField>(cell(1, 2)).controller!.text, 'hello');
    await close(tester);
  });

  testWidgets('a cell keeps focus and caret while its writes land', (
    tester,
  ) async {
    final c = await withTable(tester);
    await tester.showKeyboard(cell(0, 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await settleWrites(tester);
    expect(tables(c).single.rows[0][1], 'abc');
    final field = tester.widget<TextField>(cell(0, 1));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection.baseOffset, 2);
    await close(tester);
  });

  testWidgets('Aa > Table inserts one too', (tester) async {
    await addNote('n1', _c(''));
    final c = await open(tester, 'n1');
    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(tables(c), hasLength(1));
    expect(find.byKey(const ValueKey('table-grid')), findsOneWidget);
    await close(tester);
  });

  testWidgets('Tab moves on and Tab in the last cell adds a row', (
    tester,
  ) async {
    final c = await withTable(tester);
    await type(tester, 0, 0, 'a');
    await key(tester, LogicalKeyboardKey.tab);
    expect(tester.widget<TextField>(cell(0, 1)).focusNode!.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.tab);
    expect(tester.widget<TextField>(cell(1, 0)).focusNode!.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await key(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(tester.widget<TextField>(cell(0, 2)).focusNode!.hasFocus, isTrue);
    expect(tables(c).single.rows[0][0], 'a');

    // Walk to the last cell and Tab once more.
    for (var i = 0; i < 6; i++) {
      await key(tester, LogicalKeyboardKey.tab);
    }
    expect(tester.widget<TextField>(cell(2, 2)).focusNode!.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tables(c).single.rows, hasLength(4));
    expect(tester.widget<TextField>(cell(3, 0)).focusNode!.hasFocus, isTrue);
    await close(tester);
  });

  testWidgets('Return moves to the cell below', (tester) async {
    await withTable(tester);
    await type(tester, 0, 1, 'x');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(tester.widget<TextField>(cell(1, 1)).focusNode!.hasFocus, isTrue);
    await close(tester);
  });

  testWidgets('menu: rows, columns, header and delete', (tester) async {
    final c = await withTable(tester);
    await type(tester, 1, 1, 'mid');
    await settleWrites(tester);

    Future<void> choose(String item) async {
      await tester.tap(find.byKey(const ValueKey('table-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    await choose('Add row below');
    expect(tables(c).single.rows, hasLength(4));
    await choose('Add column right');
    expect(tables(c).single.columns, 4);
    // The cell the menu worked from (the last one focused) keeps its text.
    expect(tables(c).single.rows[1][1], 'mid');
    await choose('Delete column');
    expect(tables(c).single.columns, 3);
    await choose('Delete row');
    expect(tables(c).single.rows, hasLength(3));
    await choose('Header row');
    expect(tables(c).single.header, isFalse);
    await choose('Header row');
    expect(tables(c).single.header, isTrue);
    await choose('Delete table');
    expect(tables(c), isEmpty);
    expect(c.document.toPlainText(), '\n');
    await close(tester);
  });

  testWidgets('the note\'s undo takes back a table edit', (tester) async {
    final c = await withTable(tester);
    // Quill merges edits made within a second into one undo step.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await type(tester, 0, 0, 'abc');
    await settleWrites(tester);
    expect(tables(c).single.rows[0][0], 'abc');
    c.undo();
    await tester.pumpAndSettle();
    expect(tables(c).single.rows[0][0], '');
    expect(tester.widget<TextField>(cell(0, 0)).controller!.text, '');
    await close(tester);
  });

  test('table cell text counts as words', () {
    final doc = Document.fromJson([
      {'insert': 'one two\n'},
      {
        'insert': {
          'table': NoteTable(
            rows: [
              ['alpha beta', ''],
              ['gamma', 'delta'],
            ],
          ).encode(),
        },
      },
      {'insert': '\n'},
    ]);
    expect(noteStats(doc).words, 6);
  });

  testWidgets('damaged table data renders as a 1x1 table', (tester) async {
    await addNote(
      'n1',
      jsonEncode([
        {
          'insert': {'table': '{nonsense'},
        },
        {'insert': '\n'},
      ]),
    );
    await open(tester, 'n1');
    expect(cell(0, 0), findsOneWidget);
    expect(cell(0, 1), findsNothing);
    expect(cell(1, 0), findsNothing);
    await close(tester);
  });

  testWidgets('a read-only table is drawn as text', (tester) async {
    final data = NoteTable(
      rows: [
        ['Name', 'Age'],
        ['Ada', '36'],
      ],
    ).encode();
    final controller = QuillController(
      document: Document.fromJson([
        {
          'insert': {'table': data},
        },
        {'insert': '\n'},
      ]),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          FlutterQuillLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            config: const QuillEditorConfig(
              embedBuilders: [TableEmbedBuilder()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Format > Table (⌥⌘T) inserts a table', (tester) async {
    await addNote('n1', _c(''));
    useMacWindow(tester, macWindowSizes['laptop13']!);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          localizationsDelegates: const [
            FlutterQuillLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const NoteEditorScreen(noteId: 'n1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.focusNode.requestFocus();
    await tester.pump();
    expect(dispatchMenuCommand(MenuCommand.insertTable), isTrue);
    await tester.pumpAndSettle();
    expect(tables(editor.controller), hasLength(1));
    await close(tester);
  }, variant: macOnly);
}
