import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/notes/citation_embed.dart';
import 'package:corplex/features/notes/math_markers.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:corplex/features/projects/todos.dart';
import 'package:corplex/features/projects/todos_request.dart';

import '../../support/fake_audio_engine.dart';

String body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

/// The document the editor shows for [stored].
String shown(String stored) =>
    decodeNoteContent(citationsToEmbeds(mathToEmbeds(stored))).toPlainText();

void main() {
  group('findTodos', () {
    test('finds the three kinds in order', () {
      final todos = findTodos(
        body(
          'TODO: check the sample size\n'
          'Sleep helps memory [@?]. Next point.\n'
          'Here [fig: loss curves] and [FIG] and TODOS no.',
        ),
      );
      expect(todos.map((t) => t.kind), [
        TodoKind.todo,
        TodoKind.needsCitation,
        TodoKind.figure,
        TodoKind.figure,
      ]);
      expect(todos[0].text, 'check the sample size');
      expect(todos[1].text, 'Sleep helps memory .');
      expect(todos[2].text, 'loss curves');
      expect(todos[3].text, 'Figure');
    });

    test('TODO is case-sensitive and a whole word', () {
      expect(findTodos(body('todo later, TODOS, ATODO')), isEmpty);
      expect(findTodos(body('TODO')).single.text, 'TODO');
    });

    test('text is clipped to about 120 characters', () {
      final t = findTodos(body('TODO ${'word ' * 60}')).single;
      expect(t.text.length, lessThanOrEqualTo(122));
      expect(t.text.endsWith('…'), isTrue);
    });

    test('offsets match the editor document with chips and maths before', () {
      final stored = jsonEncode([
        {
          'insert':
              'A [@vaswani2017] and [@a2020; @b2020] then \$x^2\$ and '
              '\$\$ \\int f \$\$\n',
        },
        {'insert': 'TODO: after chips [@?] here [fig: f]\n'},
      ]);
      final plain = shown(stored);
      // Chips and maths really are embeds in the shown document.
      expect(plain.contains('￼'), isTrue);
      final todos = findTodos(stored);
      expect(todos.length, 3);
      for (final t in todos) {
        final marker = plain.substring(t.offset, t.offset + t.length);
        expect(marker, switch (t.kind) {
          TodoKind.todo => 'TODO:',
          TodoKind.needsCitation => '[@?]',
          TodoKind.figure => '[fig: f]',
        });
      }
      // The stored text would give different offsets.
      final raw = decodeNoteContent(stored).toPlainText();
      expect(raw.indexOf('TODO'), isNot(todos.first.offset));
    });

    test('[@?] is not turned into a citation chip', () {
      final stored = body('Claim [@?] and real [@a2020].');
      final plain = shown(stored);
      expect(plain, contains('[@?]'));
      expect('￼'.allMatches(plain).length, 1);
    });
  });

  group('in the app', () {
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

    Widget app(Widget home) => ProviderScope(
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
        home: home,
      ),
    );

    Future<void> addNote(String id, String title, String content) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(content),
          ),
        );

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('hidden when there are none', (tester) async {
      final p = await findOrCreateProject(db, 'T');
      await addNote('n1', 'Intro', body('Nothing to do.'));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ProjectTodosSection(
              projectId: p,
              orderedNoteIds: const ['n1'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('To do in the writing'), findsNothing);
      await dispose(tester);
    });

    testWidgets('groups by chapter and opens the note at the marker', (
      tester,
    ) async {
      final p = await findOrCreateProject(db, 'T');
      final stored = jsonEncode([
        {'insert': 'Intro [@a2020] text.\nTODO: fix this\n'},
      ]);
      await addNote('n1', 'Intro', stored);
      await addNote('n2', 'Methods', body('Fine.'));
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ProjectTodosSection(
              projectId: p,
              orderedNoteIds: const ['n2', 'n1'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('To do in the writing (1)'), findsOneWidget);
      expect(find.text('Methods'), findsNothing);
      expect(find.text('Intro'), findsOneWidget);
      await tester.tap(find.text('fix this'));
      await tester.pumpAndSettle();

      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      final sel = editor.controller.selection;
      final plain = editor.controller.document.toPlainText();
      expect(plain.substring(sel.start, sel.end), 'TODO:');
      await dispose(tester);
    });

    testWidgets('an open editor takes a selection request', (tester) async {
      await addNote('n1', 'N', body('one two three'));
      await tester.pumpWidget(app(const NoteEditorScreen(noteId: 'n1')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NoteEditorScreen)),
      );
      container.read(pendingNoteSelectionProvider.notifier).state = (
        noteId: 'n1',
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editor.controller.selection.start, 4);
      expect(editor.controller.selection.end, 7);
      expect(container.read(pendingNoteSelectionProvider), isNull);
      await dispose(tester);
    });

    testWidgets('a selection past the end is clamped', (tester) async {
      await addNote('n1', 'N', body('short'));
      await tester.pumpWidget(
        app(
          const NoteEditorScreen(
            noteId: 'n1',
            initialSelection: TextSelection(baseOffset: 90, extentOffset: 99),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editor.controller.selection.end, lessThanOrEqualTo(5));
      await dispose(tester);
    });
  });
}
