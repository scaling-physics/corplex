import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/heading_fold.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/l10n/l10n.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/fake_audio_engine.dart';
import '../../support/mac_screenshot.dart';

/// H1 One, two paragraphs, H2 Sub, a paragraph, H1 Two, a paragraph.
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

void main() {
  late AppDatabase db;
  late String original;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.inMemoryForTesting();
    original = jsonEncode(sample().toJson());
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Sections'),
            content: Value(original),
          ),
        );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<QuillController> open(
    WidgetTester tester, {
    TextSelection? initialSelection,
    bool mac = false,
  }) async {
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
          home: NoteEditorScreen(
            noteId: 'n1',
            initialSelection: initialSelection,
          ),
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

  Future<Note> row() =>
      (db.select(db.notes)..where((n) => n.id.equals('n1'))).getSingle();

  Future<void> saveWait(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  testWidgets('the caret heading shows a chevron; it folds, and "…" opens', (
    tester,
  ) async {
    final c = await open(tester);
    expect(c.document.toPlainText(), whole);
    c.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse section'), findsWidgets);

    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), 'One\n￼\nTwo\ndelta\n');
    expect(find.byTooltip('Expand section'), findsOneWidget);
    expect(find.byTooltip('Show section'), findsOneWidget);

    // Folding is not an edit: nothing is saved, nothing to undo.
    await saveWait(tester);
    final saved = await row();
    expect(saved.content, original);
    expect(c.hasUndo, isFalse);

    await tester.tap(find.byTooltip('Show section'));
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), whole);
    await saveWait(tester);
    expect((await row()).content, original);
    await close(tester);
  });

  testWidgets('typing in the visible part saves the hidden text too', (
    tester,
  ) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pumpAndSettle();
    final at = c.document.toPlainText().indexOf('delta') + 5;
    c.replaceText(at, 0, '!', null);
    await saveWait(tester);
    final doc = Document.fromJson(jsonDecode((await row()).content) as List);
    expect(doc.toPlainText(), whole.replaceFirst('delta', 'delta!'));
    await close(tester);
  });

  testWidgets('collapsed sections come back when the note is reopened', (
    tester,
  ) async {
    var c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pumpAndSettle();
    await close(tester);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('notes.folds.n1');
    expect(saved, hasLength(1));
    // Fingerprints only, never the heading's words.
    expect(saved!.join(), isNot(contains('One')));

    c = await open(tester);
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), 'One\n￼\nTwo\ndelta\n');
    await close(tester);
  });

  testWidgets('opening at a spot inside a folded section opens it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'notes.folds.n1': [foldFingerprint('n1', 'One', 0)],
    });
    final c = await open(
      tester,
      initialSelection: TextSelection(
        baseOffset: whole.indexOf('beta'),
        extentOffset: whole.indexOf('beta') + 4,
      ),
    );
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), whole);
    expect(
      c.document.toPlainText().substring(c.selection.start, c.selection.end),
      'beta',
    );
    await close(tester);

    // Without the selection the same note opens folded.
    final folded = await open(tester);
    await tester.pumpAndSettle();
    expect(folded.document.toPlainText(), 'One\n￼\nTwo\ndelta\n');
    await close(tester);
  });

  testWidgets('find in note opens the section that holds a match', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'notes.folds.n1': [foldFingerprint('n1', 'One', 0)],
    });
    final c = await open(tester);
    expect(c.document.toPlainText(), 'One\n￼\nTwo\ndelta\n');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Find in note'),
      'gamma',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
    expect(c.document.toPlainText(), whole);
    expect(
      c.document.toPlainText().substring(c.selection.start, c.selection.end),
      'gamma',
    );
    await close(tester);
  });

  testWidgets('an outside change keeps the folds', (tester) async {
    final c = await open(tester);
    c.updateSelection(
      const TextSelection.collapsed(offset: 1),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse section').first);
    await tester.pumpAndSettle();

    final changed = sample()..insert('omega\n');
    await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(
        content: Value(jsonEncode(changed.toJson())),
        updatedAt: Value(DateTime.now().add(const Duration(minutes: 1))),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), 'One\n￼\nTwo\ndelta\nomega\n');
    await close(tester);
  });

  testWidgets('menu: Collapse all sections, Expand all sections', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Expand all sections'), findsNothing);
    await tester.tap(find.text('Collapse all sections'));
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), 'One\n￼\nTwo\n￼\n');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand all sections'));
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), whole);
    await saveWait(tester);
    expect((await row()).content, original);
    await close(tester);
  });

  testWidgets('a note with no headings has no fold menu items', (tester) async {
    await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(
        content: Value(
          jsonEncode([
            {'insert': 'plain\n'},
          ]),
        ),
      ),
    );
    await open(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Collapse all sections'), findsNothing);
    expect(find.text('Expand all sections'), findsNothing);
    await close(tester);
  });

  testWidgets('Mac: hovering a heading shows its chevron', (tester) async {
    final c = await open(tester, mac: true);
    c.updateSelection(
      TextSelection.collapsed(offset: whole.indexOf('delta')),
      ChangeSource.local,
    );
    await tester.pumpAndSettle();
    // The caret is in a paragraph: no chevron is showing.
    Iterable<double> shown() => find
        .byType(AnimatedOpacity)
        .evaluate()
        .map((e) => (e.widget as AnimatedOpacity).opacity)
        .where((o) => o > 0);
    expect(shown(), isEmpty);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final sub = tester.getCenter(find.byTooltip('Collapse section').at(1));
    await mouse.moveTo(Offset(300, sub.dy));
    await tester.pumpAndSettle();
    expect(shown(), hasLength(1));

    await mouse.moveTo(sub);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse section').at(1));
    await tester.pumpAndSettle();
    expect(c.document.toPlainText(), 'One\nalpha\nbeta\nSub\n￼\nTwo\ndelta\n');
    expect(find.byTooltip('Expand section'), findsOneWidget);
    await close(tester);
  }, variant: macOnly);
}
