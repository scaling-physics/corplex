import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/figure_markers.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/projects_providers.dart';

import '../../support/fake_audio_engine.dart';

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
          title: Value('Chapter $id'),
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
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> slash(
    WidgetTester tester,
    QuillController c,
    String command,
  ) async {
    c.replaceText(
      c.selection.baseOffset,
      0,
      '/',
      TextSelection.collapsed(offset: c.selection.baseOffset + 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(command));
    await tester.pumpAndSettle();
  }

  List<String> embeds(QuillController c) => [
    for (final o in c.document.toDelta().toJson())
      if (o['insert'] is Map) (o['insert'] as Map).values.single as String,
  ];

  testWidgets('Figure caption starts a caption and numbers live', (
    tester,
  ) async {
    await addNote('n1', _c(''));
    final c = await open(tester, 'n1');
    await slash(tester, c, 'Figure caption');
    expect(embeds(c).single, startsWith('{#fig:'));
    expect(find.text('Figure 1.'), findsOneWidget);
    // The cursor sits after the chip and a space, ready for the caption.
    expect(c.selection.baseOffset, 2);
    c.replaceText(2, 0, 'Place fields', null);

    // A second caption goes on a new line, since this line has text, and
    // a table is numbered apart from figures.
    await slash(tester, c, 'Table caption');
    expect(find.text('Table 1.'), findsOneWidget);
    await slash(tester, c, 'Figure caption');
    expect(find.text('Figure 2.'), findsOneWidget);
    final plain = c.document.toPlainText();
    expect(RegExp('￼').allMatches(plain).length, 3);
    expect(plain.split('\n').where((l) => l.startsWith('￼')), hasLength(3));

    // Stored as markers, the first caption's text intact.
    final stored = storedFromEditor(c.document);
    expect(stored, contains('Place fields'));
    expect(
      findFigureMarkers(jsonDecode(stored).map((o) => o['insert']).join())
          .where((m) => m.isDefinition),
      hasLength(3),
    );
    await close(tester);
  });

  testWidgets('Refer to a figure picks from this note and other chapters', (
    tester,
  ) async {
    await addNote('n1', _c('{#fig:aa} Place fields in CA1.'));
    await addNote('n2', _c('{#tbl:bb} Animals used.\nSee '));
    final p = await findOrCreateProject(db, 'Thesis');
    await addNoteToProject(db, projectId: p, noteId: 'n1');
    await addNoteToProject(db, projectId: p, noteId: 'n2');
    await reorderChapters(db, p, ['n1', 'n2']);

    final c = await open(tester, 'n2');
    // Chapter 2's own table, numbered live with its chapter prefix.
    expect(find.text('Table 2.1.'), findsOneWidget);
    c.updateSelection(
      TextSelection.collapsed(offset: c.document.length - 1),
      ChangeSource.local,
    );
    await slash(tester, c, 'Refer to a figure or table');
    expect(find.text('Figure 1.1'), findsOneWidget);
    expect(find.text('Table 2.1'), findsOneWidget);
    expect(find.text('Place fields in CA1.'), findsOneWidget);

    // Search narrows the list.
    await tester.enterText(find.byType(TextField).last, 'animals');
    await tester.pumpAndSettle();
    expect(find.text('Figure 1.1'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'place');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Figure 1.1'));
    await tester.pumpAndSettle();

    expect(embeds(c), contains('{@fig:aa}'));
    // The chip reads the other chapter's number.
    expect(find.text('Figure 1.1'), findsOneWidget);
    expect(storedFromEditor(c.document), contains('{@fig:aa}'));
    await close(tester);
  });

  testWidgets('an unknown reference reads Figure ?? and numbers follow moves', (
    tester,
  ) async {
    await addNote('n1', _c('{#fig:aa} One\n{#fig:bb} Two\nSee {@fig:zz}'));
    final c = await open(tester, 'n1');
    expect(find.text('Figure 1.'), findsOneWidget);
    expect(find.text('Figure 2.'), findsOneWidget);
    expect(find.text('Figure ??'), findsOneWidget);

    // Deleting the first caption renumbers the second at once.
    c.replaceText(0, 1, '', null);
    await tester.pumpAndSettle();
    expect(find.text('Figure 1.'), findsOneWidget);
    expect(find.text('Figure 2.'), findsNothing);
    await close(tester);
  });

  testWidgets('tapping a reference selects its definition', (tester) async {
    await addNote('n1', _c('{#fig:aa} One\nSee {@fig:aa}'));
    final c = await open(tester, 'n1');
    await tester.tap(find.text('Figure 1').first);
    await tester.pumpAndSettle();
    expect(c.selection.start, 0);
    expect(c.selection.end, 1);
    await close(tester);
  });
}
