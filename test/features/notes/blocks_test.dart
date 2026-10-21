import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/notes/block_ops.dart';
import 'package:corplex/features/notes/contents_block.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/heading_fold.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/platform/mac_window.dart';
import 'package:corplex/l10n/l10n.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

String plain(String stored) => decodeNoteContent(stored).toPlainText();

void main() {
  group('pure', () {
    test('moving a line keeps citations, maths, block ids and formatting', () {
      final stored = jsonEncode([
        {'insert': 'First [@vaswani2017]\nSecond \$x^2\$ ^blk1\n'},
        {'insert': 'Third'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);
      final doc = editorDocument(stored);
      final lines = parseFoldLines(doc.toDelta());
      expect(lines, hasLength(3));
      final next = moveLines(lines, 1, 2, 0)!;
      final moved = Document.fromDelta(foldLinesToDelta(next));
      final back = storedFromEditor(moved);
      expect(
        plain(back),
        'Second \$x^2\$ ^blk1\nFirst [@vaswani2017]\nThird\n',
      );
      expect(decodeNoteContent(back).toDelta().last.attributes, {
        'list': 'bullet',
      });
      // Moving to where it already is changes nothing.
      expect(moveLines(lines, 1, 2, 1), isNull);
      expect(moveLines(lines, 1, 2, 2), isNull);
      // Down: the line lands after the next one.
      final down = moveLines(lines, 0, 1, 2)!;
      expect(down.map((l) => l.text).toList()[1], startsWith('First'));
    });

    test('turn into restyles, and callout / toggle add and remove markers', () {
      final line = FoldLine([Operation.insert('Idea')], {'header': 2});
      expect(turnLineInto(line, TurnInto.bullet).attrs, {'list': 'bullet'});
      expect(turnLineInto(line, TurnInto.text).attrs, isNull);
      expect(turnLineInto(line, TurnInto.code).attrs, {'code-block': 'plain'});
      final callout = turnLineInto(line, TurnInto.callout);
      expect(callout.attrs, {'blockquote': true});
      expect(callout.ops.first.data, {'callout': '[!note]'});
      expect(turnLineInto(callout, TurnInto.text).text, 'Idea');
      final toggle = turnLineInto(line, TurnInto.toggle);
      expect(
        toggle.text,
        '$toggleMark'
        'Idea',
      );
      expect(toggle.isToggle, isTrue);
      expect(turnLineInto(toggle, TurnInto.quote).text, 'Idea');
      expect(
        canTurnInto(
          FoldLine([
            Operation.insert({'sketch': '{}'}),
          ], null),
        ),
        isFalse,
      );
    });

    test('duplicate and delete', () {
      final a = FoldLine([Operation.insert('a')], null);
      final b = FoldLine([Operation.insert('b')], {'header': 1});
      expect(duplicateLines([a, b], 1, 2).map((l) => l.text), ['a', 'b', 'b']);
      expect(deleteLines([a, b], 0, 1).single.text, 'b');
      expect(deleteLines([a], 0, 1).single.text, '');
    });

    test('a toggle folds its indented children and stores plain text', () {
      final delta = Delta()
        ..insert(
          '$toggleMark'
          'Why',
        )
        ..insert('\n')
        ..insert('because')
        ..insert('\n', {'indent': 1})
        ..insert('really')
        ..insert('\n', {'indent': 1})
        ..insert('after\n');
      final lines = parseFoldLines(delta);
      expect(sectionEnd(lines, 0), 3);
      expect(canCollapse(lines, 0), isTrue);
      final folded = collapseLine(lines, 0)!;
      expect(folded, hasLength(3));
      expect(folded[1].isFold, isTrue);
      final live = foldLinesToDelta(folded);
      // Stored form: every fold put back, nothing else changed.
      expect(
        storedFromEditor(Document.fromDelta(live)),
        encodeNoteContent(Document.fromDelta(delta)),
      );
      expect(collapsedFingerprints(live, 'n').length, 1);
      expect(
        expandLines(folded).map((l) => l.signature),
        lines.map((l) => l.signature),
      );
    });

    test('contents lines list the headings', () {
      final delta = Delta()
        ..insert('Intro')
        ..insert('\n', {'header': 1})
        ..insert('text\n')
        ..insert('Method')
        ..insert('\n', {'header': 2});
      expect(contentsLines(delta), ['Intro', '  Method']);
      expect(contentsLines(Delta()..insert('x\n')), isEmpty);
    });
  });

  group('export', () {
    test('a contents block exports as a plain list of headings', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      final content = jsonEncode(
        (Delta()
              ..insert({'contents': '{}'})
              ..insert('\n')
              ..insert('Intro')
              ..insert('\n', {'header': 1})
              ..insert('Method')
              ..insert('\n', {'header': 2}))
            .toJson(),
      );
      final doc = await buildExportDoc(db, [
        ExportNote('Note', content),
      ], title: 'Note');
      final bullets = [
        for (final b in doc.blocks)
          if (b.kind == BlockKind.bullet) b.text,
      ];
      expect(bullets, ['Intro', 'Method']);
    });
  });

  group('editor', () {
    late AppDatabase db;
    setUp(() {
      EditableText.debugDeterministicCursor = true;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() {
      EditableText.debugDeterministicCursor = false;
      db.close();
    });

    Future<QuillController> open(
      WidgetTester tester,
      Delta content, {
      bool mac = false,
    }) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Blocks'),
              content: Value(jsonEncode(content.toJson())),
            ),
          );
      if (mac) {
        useMacWindow(tester, macWindowSizes['laptop13']!);
      } else {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NoteEditorScreen(noteId: 'n1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Delta sample() => Delta()
      ..insert('One')
      ..insert('\n', {'header': 1})
      ..insert('alpha\nbeta\n')
      ..insert('Sub')
      ..insert('\n', {'header': 2})
      ..insert('gamma\n');

    testWidgets('Mac: the move-block commands reorder lines, one undo each', (
      tester,
    ) async {
      final c = await open(tester, sample(), mac: true);
      await tester.tap(find.textContaining('alpha', findRichText: true));
      await tester.pumpAndSettle();
      expect(dispatchMenuCommand(MenuCommand.moveBlockDown), isTrue);
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'One\nbeta\nalpha\nSub\ngamma\n');
      expect(dispatchMenuCommand(MenuCommand.moveBlockUp), isTrue);
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'One\nalpha\nbeta\nSub\ngamma\n');
      c.undo();
      expect(c.document.toPlainText(), 'One\nbeta\nalpha\nSub\ngamma\n');
      c.undo();
      expect(c.document.toPlainText(), 'One\nalpha\nbeta\nSub\ngamma\n');
      await close(tester);
    }, variant: macOnly);

    testWidgets('Mac: the handle is hidden until hover, then turns a line '
        'into a bulleted list', (tester) async {
      final c = await open(tester, sample(), mac: true);
      bool handleShown() => find
          .ancestor(
            of: find.byIcon(Icons.drag_indicator),
            matching: find.byType(AnimatedOpacity),
          )
          .evaluate()
          .any((e) => (e.widget as AnimatedOpacity).opacity > 0);
      expect(handleShown(), isFalse);

      final line = tester.getRect(
        find.textContaining('alpha', findRichText: true),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // Over the text itself (not the margin): still nothing.
      await mouse.moveTo(Offset(line.left + 60, line.center.dy));
      await tester.pumpAndSettle();
      expect(handleShown(), isFalse);

      await mouse.moveTo(Offset(line.left - 10, line.center.dy));
      await tester.pumpAndSettle();
      expect(handleShown(), isTrue);

      await tester.tap(find.byIcon(Icons.drag_indicator));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn into'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulleted list'));
      await tester.pumpAndSettle();
      final attrs = c.document.toDelta().toList().firstWhere(
        (o) => o.data == '\n' && o.attributes?['list'] != null,
      );
      expect(attrs.attributes, {'list': 'bullet'});
      expect(c.document.toPlainText(), 'One\nalpha\nbeta\nSub\ngamma\n');
      await close(tester);
    }, variant: macOnly);

    testWidgets('Mac: dragging a handle moves the line', (tester) async {
      final c = await open(tester, sample(), mac: true);
      final line = tester.getRect(
        find.textContaining('alpha', findRichText: true),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(Offset(line.left - 10, line.center.dy));
      await tester.pumpAndSettle();
      final handle = tester.getCenter(find.byIcon(Icons.drag_indicator));
      final drag = await tester.startGesture(
        handle,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 8));
      await drag.moveBy(Offset(0, line.height * 1.8));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'One\nbeta\nalpha\nSub\ngamma\n');
      await close(tester);
    }, variant: macOnly);

    testWidgets('Mac: Ctrl+Cmd+Down moves the block holding the caret', (
      tester,
    ) async {
      final c = await open(tester, sample(), mac: true);
      await tester.tap(find.textContaining('alpha', findRichText: true));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'One\nbeta\nalpha\nSub\ngamma\n');
      await close(tester);
    }, variant: macOnly);

    testWidgets('a collapsed toggle moves with its fold and saves whole', (
      tester,
    ) async {
      final content = Delta()
        ..insert(
          '$toggleMark'
          'T',
        )
        ..insert('\n')
        ..insert('child')
        ..insert('\n', {'indent': 1})
        ..insert('x\ny\n');
      final c = await open(tester, content, mac: true);
      c.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse section').first);
      await tester.pumpAndSettle();
      expect(
        c.document.toPlainText(),
        '$toggleMark'
        'T\n￼\nx\ny\n',
      );
      await tester.tap(find.textContaining('T', findRichText: true).first);
      await tester.pumpAndSettle();
      c.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      await tester.pump();
      expect(dispatchMenuCommand(MenuCommand.moveBlockDown), isTrue);
      await tester.pumpAndSettle();
      expect(
        c.document.toPlainText(),
        'x\n$toggleMark'
        'T\n￼\ny\n',
      );
      await tester.pump(const Duration(milliseconds: 600));
      final row = await db.select(db.notes).getSingle();
      expect(
        plain(row.content),
        'x\n$toggleMark'
        'T\nchild\ny\n',
      );
      await close(tester);
    }, variant: macOnly);

    testWidgets('a toggle gets the chevron and folds its children', (
      tester,
    ) async {
      final content = Delta()
        ..insert(
          '$toggleMark'
          'Why',
        )
        ..insert('\n')
        ..insert('because')
        ..insert('\n', {'indent': 1})
        ..insert('after\n');
      final c = await open(tester, content);
      c.updateSelection(
        const TextSelection.collapsed(offset: 3),
        ChangeSource.local,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse section').first);
      await tester.pumpAndSettle();
      expect(
        c.document.toPlainText(),
        '$toggleMark'
        'Why\n￼\nafter\n',
      );
      await tester.tap(find.byTooltip('Show section'));
      await tester.pumpAndSettle();
      expect(
        c.document.toPlainText(),
        '$toggleMark'
        'Why\nbecause\nafter\n',
      );
      // Nothing was an edit.
      await tester.pump(const Duration(milliseconds: 600));
      final row = await (db.select(db.notes)).getSingle();
      expect(
        plain(row.content),
        '$toggleMark'
        'Why\nbecause\nafter\n',
      );
      await close(tester);
    });

    testWidgets('a contents block lists the headings and jumps', (
      tester,
    ) async {
      final content = Delta()
        ..insert({'contents': '{}'})
        ..insert('\n')
        ..insert('Intro')
        ..insert('\n', {'header': 1})
        ..insert('text\n' * 6)
        ..insert('Method')
        ..insert('\n', {'header': 2})
        ..insert('end\n');
      final c = await open(tester, content);
      // Once in the contents block, once in the note.
      expect(find.text('Intro', findRichText: true), findsWidgets);
      expect(find.text('Method', findRichText: true), findsWidgets);
      await tester.tap(find.widgetWithText(InkWell, 'Method'));
      await tester.pumpAndSettle();
      final at = c.document.toPlainText().indexOf('Method');
      expect(c.selection.baseOffset, at);

      // Live: a new heading appears in the list.
      c.replaceText(
        c.document.length - 1,
        0,
        'Extra',
        const TextSelection.collapsed(offset: 0),
      );
      c.formatText(c.document.length - 1, 0, Attribute.h2);
      await tester.pumpAndSettle();
      expect(find.text('endExtra', findRichText: true), findsWidgets);
      await close(tester);
    });
  });
}
