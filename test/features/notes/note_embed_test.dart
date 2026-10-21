import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_embed.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/l10n_app.dart';

String _long() => jsonEncode([
  {'insert': 'Methods'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'We counted spikes. ^m1\n'},
  for (var i = 0; i < 14; i++) {'insert': 'Filler line number $i\n'},
  {'insert': 'Results'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'It worked.\n'},
]);

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    EditableText.debugDeterministicCursor = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() async {
    EditableText.debugDeterministicCursor = false;
    await db.close();
  });

  Future<void> note(String id, String title, String content) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(content),
        ),
      );

  Future<void> show(WidgetTester tester, NoteLinkTarget target) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: NoteEmbedCard(target: target),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('shows the section of a note, read-only, with its title', (
    tester,
  ) async {
    await note('b', 'Field notes', _long());
    await show(tester, const NoteLinkTarget('b', heading: 'Results'));
    expect(find.text('Field notes › Results'), findsOneWidget);
    expect(
      find.textContaining('It worked.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Filler', findRichText: true), findsNothing);
    expect(find.text('Show all'), findsNothing);
    await dispose(tester);
  });

  testWidgets('a block embed shows its paragraph without the marker', (
    tester,
  ) async {
    await note('b', 'Field notes', _long());
    await show(tester, const NoteLinkTarget('b', block: 'm1'));
    expect(
      find.textContaining('We counted spikes.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('^m1', findRichText: true), findsNothing);
    await dispose(tester);
  });

  testWidgets('a long note is capped, with Show all', (tester) async {
    await note('b', 'Field notes', _long());
    await show(tester, const NoteLinkTarget('b'));
    expect(find.text('Show all'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('follows the target live', (tester) async {
    await note('b', 'Field notes', _long());
    await show(tester, const NoteLinkTarget('b', heading: 'Results'));
    await tester.runAsync(() async {
      await (db.update(db.notes)..where((n) => n.id.equals('b'))).write(
        NotesCompanion(
          content: Value(
            _long().replaceFirst('It worked.', 'It worked, twice.'),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('It worked, twice.', findRichText: true),
      findsOneWidget,
    );
    await dispose(tester);
  });

  testWidgets('missing note, missing section and locked note', (tester) async {
    await show(tester, const NoteLinkTarget('gone'));
    expect(find.text('Note not found'), findsOneWidget);

    await note('b', 'Field notes', _long());
    await show(tester, const NoteLinkTarget('b', heading: 'Nope'));
    expect(find.text('Section not found'), findsOneWidget);

    await note('l', 'Secret', 'corplex-locked:v1:k:AAAA');
    await show(tester, const NoteLinkTarget('l'));
    expect(find.text('Secret'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('an embed inside an embedded note is only a title', (
    tester,
  ) async {
    await note(
      'inner',
      'Inner note',
      jsonEncode([
        {'insert': 'Inner text\n'},
      ]),
    );
    await note(
      'outer',
      'Outer note',
      jsonEncode([
        {'insert': 'Outer text\n'},
        {
          'insert': {noteEmbedType: noteEmbedData(noteLink('inner'))},
        },
        {'insert': '\n'},
      ]),
    );
    await show(tester, const NoteLinkTarget('outer'));
    expect(
      find.textContaining('Outer text', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Inner note'), findsOneWidget);
    expect(find.textContaining('Inner text', findRichText: true), findsNothing);
    await dispose(tester);
  });

  test('an embed is one block line in the editor document', () {
    final stored = jsonEncode([
      {'insert': 'Before\n'},
      {
        'insert': {noteEmbedType: noteEmbedData(noteLink('b'))},
      },
      {'insert': '\nAfter\n'},
    ]);
    final doc = editorDocument(stored);
    expect(doc.toPlainText(), 'Before\n￼\nAfter\n');
    // Round-trips and carries the link text for backlinks and the Map.
    expect(storedFromEditor(doc), encodeNoteContent(decodeNoteContent(stored)));
    expect(storedFromEditor(doc), contains('corplex://note/b'));
  });

  test('inserting an embed puts it on a line of its own', () {
    final controller = QuillController(
      document: Document()..insert(0, 'ab'),
      selection: const TextSelection.collapsed(offset: 1),
    );
    insertNoteEmbed(controller, noteLink('b'));
    expect(controller.document.toPlainText(), 'a\n￼\nb\n');

    final end = QuillController(
      document: Document()..insert(0, 'ab'),
      selection: const TextSelection.collapsed(offset: 2),
    );
    insertNoteEmbed(end, noteLink('b'));
    expect(end.document.toPlainText(), 'ab\n￼\n\n');
    expect(end.selection.baseOffset, end.document.length - 1);
  });
}
