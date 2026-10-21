import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/authors.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';

import '../support/fake_audio_engine.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    // A phone.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
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
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  test('author summaries', () {
    String summary(String raw) => authorsSummary(parseAuthors(raw));
    expect(summary('Vaswani, Ashish'), 'Ashish Vaswani');
    expect(
      summary('Vaswani, Ashish; Shazeer, Noam'),
      'Ashish Vaswani and Noam Shazeer',
    );
    expect(
      summary(
        'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki; Uszkoreit, Jakob; '
        'Jones, Llion',
      ),
      'Ashish Vaswani, Noam Shazeer, Niki Parmar + 2 more',
    );
    expect(summary(''), '');
  });

  testWidgets('a long note title wraps, and Return moves to the body', (
    tester,
  ) async {
    const title =
        'Figure from Attention Is All You Need, page four, the encoder stack';
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value(title),
          ),
        );
    await show(tester, const NoteEditorScreen(noteId: 'n1'));

    final field = find.widgetWithText(TextField, title);
    expect(tester.getSize(field).height, greaterThan(60), reason: 'wrapped');

    await tester.tap(field);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode.hasFocus,
      isTrue,
    );
    expect(
      (await db.select(db.notes).getSingle()).title,
      title,
      reason: 'no newline in the title',
    );
    await close(tester);
  });

  testWidgets('the formatting row fits a phone, rarer styles under Aa', (
    tester,
  ) async {
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await show(tester, const NoteEditorScreen(noteId: 'n1'));

    for (final tooltip in [
      'Draw',
      'Bold',
      'Italic',
      'Underline',
      'Text style',
    ]) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.right, lessThanOrEqualTo(360), reason: '$tooltip on screen');
    }

    final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
    editor.controller.replaceText(
      0,
      0,
      'Method',
      const TextSelection.collapsed(offset: 3),
    );
    await tester.tap(find.byTooltip('Text style'));
    await tester.pumpAndSettle();
    expect(find.text('Body text'), findsOneWidget);
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();
    expect(
      editor.controller.getSelectionStyle().attributes['header']?.value,
      2,
    );
    await close(tester);
  });

  testWidgets('typing / opens the note commands', (tester) async {
    await db
        .into(db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await show(tester, const NoteEditorScreen(noteId: 'n1'));
    final controller = tester
        .widget<QuillEditor>(find.byType(QuillEditor))
        .controller;
    void type(String text) {
      final at = controller.selection.baseOffset.clamp(
        0,
        controller.document.length - 1,
      );
      controller.replaceText(
        at,
        0,
        text,
        TextSelection.collapsed(offset: at + text.length),
      );
    }

    // In the middle of a word it's just a slash.
    type('and/or ');
    await tester.pumpAndSettle();
    expect(find.text('Cite a paper'), findsNothing);

    // After a space: the commands. Dismissing keeps the "/".
    type('/');
    await tester.pumpAndSettle();
    expect(find.text('Cite a paper'), findsOneWidget);
    expect(find.text('Literature note template'), findsOneWidget);
    // The list now fills the screen, so there is no barrier left to tap.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), 'and/or /\n');

    // Choosing one removes the "/" and does it.
    type('Method ');
    type('/');
    await tester.pumpAndSettle();
    // The list scrolls on a short screen.
    await tester.ensureVisible(find.text('Heading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading'));
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), 'and/or /Method \n');
    expect(controller.getSelectionStyle().attributes['header']?.value, 2);
    await close(tester);
  });

  testWidgets('a long author list reads as a summary until tapped', (
    tester,
  ) async {
    const stored =
        'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki; Uszkoreit, Jakob';
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value(stored),
          ),
        );
    await show(tester, const PaperDetailScreen(paperId: 'p1'));

    expect(
      find.text('Ashish Vaswani, Noam Shazeer, Niki Parmar + 1 more'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, stored), findsNothing);

    await tester.tap(
      find.text('Ashish Vaswani, Noam Shazeer, Niki Parmar + 1 more'),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, stored), findsOneWidget);
    expect(find.text('Separate authors with ;'), findsOneWidget);
    await close(tester);
  });
}
