import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_link_sheet.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/l10n_app.dart';

final _target = jsonEncode([
  {'insert': 'Methods'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'We counted spikes.\nA second paragraph. ^keep01\n'},
  {'insert': 'Results'},
  {
    'insert': '\n',
    'attributes': {'header': 2},
  },
  {'insert': 'It worked.\n'},
]);

void main() {
  group('parseLinkQuery', () {
    test('a plain query is just a title', () {
      final q = parseLinkQuery('  Hippo ');
      expect((q.title, q.part, q.filter), ('Hippo', LinkPart.none, ''));
    });

    test('Title#Head targets a heading', () {
      final q = parseLinkQuery('Hippo#Meth');
      expect((q.title, q.part, q.filter), ('Hippo', LinkPart.heading, 'Meth'));
      final bare = parseLinkQuery('Hippo#');
      expect(
        (bare.title, bare.part, bare.filter),
        ('Hippo', LinkPart.heading, ''),
      );
    });

    test('Title#^ targets a paragraph', () {
      final q = parseLinkQuery('Hippo#^claim');
      expect((q.title, q.part, q.filter), ('Hippo', LinkPart.block, 'claim'));
      expect(parseLinkQuery('Hippo#^').part, LinkPart.block);
    });

    test('#Head alone is about the open note', () {
      final q = parseLinkQuery('#Intro');
      expect((q.title, q.part, q.filter), ('', LinkPart.heading, 'Intro'));
    });
  });

  group('the picker', () {
    late AppDatabase db;
    NoteLinkPick? picked;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      EditableText.debugDeterministicCursor = true;
      picked = null;
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() async {
      EditableText.debugDeterministicCursor = false;
      await db.close();
    });

    Future<void> open(WidgetTester tester, {bool embed = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      picked = await showNoteLinkSheet(
                        context,
                        ref,
                        excludeNoteId: 'host',
                        embed: embed,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> seed() async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('t'),
              title: const Value('Mouse model'),
              content: Value(_target),
              aliases: const Value('Murine; Rodent'),
            ),
          );
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('matches by alias and links with the alias as text', (
      tester,
    ) async {
      await seed();
      await open(tester);
      await tester.enterText(find.byType(TextField), 'rodent');
      await tester.pumpAndSettle();
      expect(find.text('Mouse model'), findsOneWidget);
      expect(find.text('Rodent'), findsOneWidget);
      await tester.tap(find.text('Mouse model'));
      await tester.pumpAndSettle();
      expect(picked?.id, 't');
      expect(picked?.title, 'Rodent');
      expect(picked?.link, noteLink('t'));
      await dispose(tester);
    });

    testWidgets('Title# lists headings; picking one links to it', (
      tester,
    ) async {
      await seed();
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Mouse model#');
      await tester.pumpAndSettle();
      expect(find.text('Methods'), findsOneWidget);
      expect(find.text('Results'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Mouse model#res');
      await tester.pumpAndSettle();
      expect(find.text('Methods'), findsNothing);
      await tester.tap(find.text('Results'));
      await tester.pumpAndSettle();
      expect(picked?.heading, 'Results');
      expect(picked?.title, 'Mouse model › Results');
      expect(
        parseNoteLinkTarget(picked!.link),
        const NoteLinkTarget('t', heading: 'Results'),
      );
      await dispose(tester);
    });

    testWidgets('Title#^ lists paragraphs; picking one marks it', (
      tester,
    ) async {
      await seed();
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Mouse model#^');
      await tester.pumpAndSettle();
      expect(find.text('We counted spikes.'), findsOneWidget);
      expect(find.text('^keep01'), findsOneWidget);
      // A paragraph without an id gets one, written to that note.
      await tester.tap(find.text('It worked.'));
      await tester.pumpAndSettle();
      final id = picked!.block!;
      expect(id, matches(RegExp(r'^[a-z0-9]{6}$')));
      expect(picked!.title, 'Mouse model › It worked.');
      final row = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('t'))).getSingle();
      expect(
        decodeNoteContent(row.content).toPlainText(),
        contains('It worked. ^$id\n'),
      );
      await dispose(tester);
    });

    testWidgets('a paragraph that has an id keeps it', (tester) async {
      await seed();
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Mouse model#^');
      await tester.pumpAndSettle();
      await tester.tap(find.text('A second paragraph.'));
      await tester.pumpAndSettle();
      expect(picked?.block, 'keep01');
      await dispose(tester);
    });

    testWidgets('a locked note can only be linked whole', (tester) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('l'),
              title: const Value('Secret'),
              content: const Value('corplex-locked:v1:k:AAAA'),
            ),
          );
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Secret#');
      await tester.pumpAndSettle();
      expect(find.textContaining('locked note can only'), findsOneWidget);
      await tester.tap(find.text('Secret'));
      await tester.pumpAndSettle();
      expect(picked?.link, noteLink('l'));
      await dispose(tester);
    });
  });
}
