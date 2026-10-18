import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/comments/comment_marks.dart';
import 'package:corplex/features/comments/comments_data.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/features/spell/note_spell.dart';
import 'package:corplex/features/spell/spell_checker.dart';
import 'package:corplex/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

const _text = 'Replay happens during sleep. The hippocampus replays sequences.';

String _body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

class _FakeSpell implements SpellChecker {
  @override
  bool get available => true;
  @override
  Future<List<List<TextRange>>> check(List<String> texts) async => [
    for (final t in texts)
      [
        for (final m in RegExp(r'[A-Za-z]+').allMatches(t))
          if (const {'hippocampus', 'teh'}.contains(m.group(0)!.toLowerCase()))
            TextRange(start: m.start, end: m.end),
      ],
  ];
  @override
  Future<List<String>> guesses(String word) async => const [];
  @override
  Future<void> learn(String word) async {}
}

void main() {
  late AppDatabase db;
  late NoteLockService lock;

  setUpAll(loadMacFonts);
  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    lock = NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n'),
            title: const Value('Chapter 2'),
            content: Value(_body(_text)),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      noteLockServiceProvider.overrideWith((ref) => lock),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<String> addRow({
    String quote = 'hippocampus',
    int anchor = 33,
    String body = 'Define this',
    String? author,
    bool resolved = false,
    DateTime? at,
  }) async {
    final id = 'c${DateTime.now().microsecondsSinceEpoch}$quote';
    await db
        .into(db.noteComments)
        .insert(
          NoteCommentsCompanion.insert(
            id: Value(id),
            noteId: 'n',
            quote: Value(quote),
            anchor: Value(anchor),
            body: Value(body),
            author: Value(author),
            resolved: Value(resolved),
            createdAt: Value(at ?? DateTime.now()),
          ),
        );
    return id;
  }

  QuillController controllerOf(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(app(const NoteEditorScreen(noteId: 'n')));
    await tester.pumpAndSettle();
  }

  group('marks over the editor', () {
    testWidgets('tint and spell-check underline coexist', (tester) async {
      final c = QuillController(
        document: Document()..insert(0, 'a teh x hippocampus y\n'),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(c.dispose);
      final spell = NoteSpell(controller: c, checker: _FakeSpell.new)
        ..enabled = true
        ..addListener(() {});
      addTearDown(spell.dispose);
      final marks = CommentMarks(c);
      addTearDown(marks.dispose);
      final row = NoteComment(
        id: 'x',
        noteId: 'n',
        quote: 'teh x hippocampus',
        anchor: 2,
        body: 'b',
        resolved: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      marks.setComments([CommentView(row, row.quote, row.body)]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates:
              FlutterQuillLocalizations.localizationsDelegates,
          home: Scaffold(
            body: QuillEditor.basic(
              controller: c,
              focusNode: FocusNode(),
              config: QuillEditorConfig(
                textSpanBuilder: marks.wrap(spell.spanBuilder),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final leaves = <TextSpan>[];
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((s) {
          if (s is TextSpan && s.text != null) leaves.add(s);
          return true;
        });
      }
      TextSpan leaf(String t) => leaves.firstWhere((s) => s.text == t);
      // Both words are misspelled-underlined AND inside the tinted passage.
      final teh = leaf('teh');
      expect(teh.style?.decoration, TextDecoration.underline);
      expect(teh.style?.backgroundColor, isNotNull);
      final hippo = leaf('hippocampus');
      expect(hippo.style?.decoration, TextDecoration.underline);
      expect(hippo.style?.backgroundColor, isNotNull);
      // Text outside the passage has neither.
      final outside = leaves.firstWhere((s) => s.text == 'a ');
      expect(outside.style?.backgroundColor, isNull);
      await close(tester);
    });

    testWidgets('tapping a commented passage offers Resolve / Edit / Delete', (
      tester,
    ) async {
      phone(tester);
      final id = await addRow(body: 'Define this');
      await openEditor(tester);
      final rt = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('hippocampus'),
      );
      final box = tester.getRect(rt.first);
      final at = _text.indexOf('hippocampus') + 5;
      await tester.tapAt(
        Offset(box.left + box.width * at / _text.length, box.top + 8),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comment-popover')), findsOneWidget);
      expect(find.text('Define this'), findsOneWidget);
      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();
      final row = await db.select(db.noteComments).getSingle();
      expect(row.id, id);
      expect(row.resolved, isTrue);
      await close(tester);
    });

    testWidgets('resolved comments are not tinted', (tester) async {
      final c = QuillController(
        document: Document()..insert(0, 'one two three\n'),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(c.dispose);
      final marks = CommentMarks(c);
      addTearDown(marks.dispose);
      NoteComment row(bool resolved) => NoteComment(
        id: 'x$resolved',
        noteId: 'n',
        quote: 'two',
        anchor: 4,
        body: 'b',
        resolved: resolved,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      marks.setComments([CommentView(row(true), 'two', 'b')]);
      expect(marks.ranges, isEmpty);
      marks.setComments([CommentView(row(false), 'two', 'b')]);
      expect(marks.ranges.single.span, (start: 4, end: 7));
      expect(marks.at(5), hasLength(1));
      expect(marks.at(8), isEmpty);
    });
  });

  group('adding', () {
    testWidgets('Option-Command-K on a selection stores quote and anchor', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await openEditor(tester);
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      editor.focusNode.requestFocus();
      await tester.pump();
      final start = _text.indexOf('The hippocampus');
      editor.controller.updateSelection(
        TextSelection(baseOffset: start, extentOffset: start + 15),
        ChangeSource.local,
      );
      await tester.pump();

      expect(dispatchMenuCommand(MenuCommand.addComment), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Add comment'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('comment-body')),
        'Which sequences?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('comment-author')),
        'Supervisor',
      );
      await tester.tap(find.byKey(const ValueKey('comment-save')));
      await tester.pumpAndSettle();

      final rows = await db.select(db.noteComments).get();
      expect(rows, hasLength(1));
      expect(rows.single.quote, 'The hippocampus');
      expect(rows.single.anchor, start);
      expect(rows.single.body, 'Which sequences?');
      expect(rows.single.author, 'Supervisor');
      await close(tester);
    }, variant: macOnly);

    testWidgets('with nothing selected the command says what to do', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await openEditor(tester);
      tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .focusNode
          .requestFocus();
      await tester.pump();
      expect(dispatchMenuCommand(MenuCommand.addComment), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Select the passage to comment on.'), findsOneWidget);
      expect(await db.select(db.noteComments).get(), isEmpty);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await close(tester);
    }, variant: macOnly);

    testWidgets('a plain note shows no comments chrome', (tester) async {
      phone(tester);
      await openEditor(tester);
      expect(find.byKey(const ValueKey('comments-panel')), findsNothing);
      expect(find.textContaining('comment'), findsNothing);
      await close(tester);
    });
  });

  group('panel', () {
    Future<void> openPanel(WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(const NoteEditorScreen(noteId: 'n')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists open comments newest first, resolved behind a toggle', (
      tester,
    ) async {
      await addRow(
        quote: 'Replay happens',
        anchor: 0,
        body: 'Older note',
        at: DateTime(2026, 1, 1),
      );
      await addRow(
        quote: 'hippocampus',
        body: 'Newer note',
        author: 'Supervisor',
        at: DateTime(2026, 2, 1),
      );
      await addRow(body: 'Done already', resolved: true);
      await openPanel(tester);

      expect(find.byKey(const ValueKey('comments-panel')), findsOneWidget);
      final newer = tester.getTopLeft(find.text('Newer note')).dy;
      final older = tester.getTopLeft(find.text('Older note')).dy;
      expect(newer, lessThan(older));
      expect(find.textContaining('Supervisor'), findsOneWidget);
      expect(find.text('Done already'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('comments-show-resolved')));
      await tester.pumpAndSettle();
      expect(find.text('Done already'), findsOneWidget);
      await close(tester);
    });

    testWidgets('tapping a comment selects its passage; moved text is found', (
      tester,
    ) async {
      // The anchor is stale (text was added above since): quote still wins.
      await addRow(quote: 'hippocampus', anchor: 2, body: 'Define this');
      await openPanel(tester);
      await tester.tap(find.text('Define this'));
      await tester.pumpAndSettle();
      final sel = controllerOf(tester).selection;
      final at = _text.indexOf('hippocampus');
      expect(sel, TextSelection(baseOffset: at, extentOffset: at + 11));
      await close(tester);
    });

    testWidgets(
      'a vanished passage shows "Passage changed" and keeps the comment',
      (tester) async {
        await addRow(quote: 'amygdala', body: 'Where did this go');
        await openEditor(tester);
        await openPanel(tester);
        expect(find.textContaining('Passage changed'), findsOneWidget);
        expect(find.text('Where did this go'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('resolve, reopen, delete with undo', (tester) async {
      final id = await addRow(body: 'Fix wording');
      await openPanel(tester);

      Future<void> choose(String label) async {
        await tester.tap(find.byKey(ValueKey('comment-menu-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('Resolve');
      expect((await db.select(db.noteComments).getSingle()).resolved, isTrue);
      expect(find.text('Fix wording'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('comments-show-resolved')));
      await tester.pumpAndSettle();
      await choose('Reopen');
      expect((await db.select(db.noteComments).getSingle()).resolved, isFalse);

      await choose('Delete');
      expect(await db.select(db.noteComments).get(), isEmpty);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        (await db.select(db.noteComments).getSingle()).body,
        'Fix wording',
      );
      expect(find.text('Fix wording'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 7));
      await close(tester);
    });

    testWidgets('side panel on a wide Mac window', (tester) async {
      await addRow(body: 'Side by side');
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await openEditor(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comments'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Side by side'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('comments-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('comments-panel')), findsNothing);
      await close(tester);
    }, variant: macOnly);
  });

  group('locked notes', () {
    testWidgets('a comment on an unlocked locked note is stored encrypted', (
      tester,
    ) async {
      useMacWindow(tester, macWindowSizes['laptop13']!);
      await tester.runAsync(() async {
        await lock.setPassword('hunter22');
        await lock.lockNote('n');
      });
      await openEditor(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editor.controller.document.toPlainText(), contains('hippocampus'));
      editor.focusNode.requestFocus();
      await tester.pump();
      final at = _text.indexOf('hippocampus');
      editor.controller.updateSelection(
        TextSelection(baseOffset: at, extentOffset: at + 11),
        ChangeSource.local,
      );
      await tester.pump();
      expect(dispatchMenuCommand(MenuCommand.addComment), isTrue);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('comment-body')),
        'Secret feedback',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('comment-save')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      final row = await tester.runAsync(
        () => db.select(db.noteComments).getSingle(),
      );
      expect(isLockedContent(row!.quote), isTrue);
      expect(isLockedContent(row.body), isTrue);
      expect(row.body, isNot(contains('Secret')));
      expect(row.anchor, at);

      // Locking the notes hides the editor; the comment stays encrypted.
      await tester.runAsync(() async {
        lock.lockNow();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(QuillEditor), findsNothing);
      expect(find.text('Secret feedback'), findsNothing);
      await close(tester);
    }, variant: macOnly);
  });
}
