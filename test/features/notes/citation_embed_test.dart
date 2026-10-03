import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/notes/citation_embed.dart';
import 'package:corplex/features/notes/note_bibliography.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';

import '../../support/fake_audio_engine.dart';

String _stored(List<Map<String, Object?>> ops) =>
    encodeNoteContent(Document.fromJson(ops));

void main() {
  group('stored text ⇄ editor chips', () {
    test('markers become chips and come back exactly', () {
      final stored = _stored([
        {'insert': 'Attention '},
        {
          'insert': 'is all [@vaswani2017; @devlin2019]',
          'attributes': {'bold': true},
        },
        {'insert': ' you need [@vaswani2017].\n'},
      ]);
      final editor = jsonDecode(citationsToEmbeds(stored)) as List;
      expect(
        editor,
        contains(
          equals({
            'insert': {'cite': '[@vaswani2017; @devlin2019]'},
            'attributes': {'bold': true},
          }),
        ),
      );
      expect(
        editor,
        contains(
          equals({
            'insert': {'cite': '[@vaswani2017]'},
          }),
        ),
      );
      expect(citationEmbedsToText(citationsToEmbeds(stored)), stored);
    });

    test('brackets that are not citations stay text', () {
      final stored = _stored([
        {'insert': 'email [@ me later] and [1]\n'},
      ]);
      expect(citationsToEmbeds(stored), stored);
    });

    test('old plain-text notes pass through untouched', () {
      expect(citationsToEmbeds('plain [@x]'), 'plain [@x]');
    });

    test('the bibliography finds citations shown as chips', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('a'),
              title: 'Alpha',
              authors: const Value('Smith, Jo'),
              year: const Value(2020),
              citekey: const Value('smith2020'),
            ),
          );
      final controller = QuillController(
        document: decodeNoteContent(
          citationsToEmbeds(
            _stored([
              {'insert': 'Claim [@smith2020].\n'},
            ]),
          ),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      expect(await insertBibliography(controller, db, CitationStyle.apa), 1);
      expect(controller.document.toPlainText(), contains('Smith, J. (2020)'));
    });
  });

  group('in the editor', () {
    late AppDatabase db;

    setUp(() async {
      EditableText.debugDeterministicCursor = true;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Attention Is All You Need',
              authors: const Value(
                'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki',
              ),
              year: const Value(2017),
              citekey: const Value('vaswani2017'),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Review'),
              content: Value(
                _stored([
                  {
                    'insert':
                        'Self-attention [@vaswani2017] and [@nobody2020].\n',
                  },
                ]),
              ),
            ),
          );
    });
    tearDown(() {
      EditableText.debugDeterministicCursor = false;
      db.close();
    });

    testWidgets('citations read as (Author et al., year) and save as keys', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              FlutterQuillLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: NoteEditorScreen(noteId: 'n1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('(Vaswani et al., 2017)'), findsOneWidget);
      expect(
        find.text('[@nobody2020]'),
        findsOneWidget,
        reason: 'an unknown key shows as written',
      );

      // Typing elsewhere saves the note with its citations still as keys.
      final controller = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .controller;
      controller.replaceText(0, 0, 'Note: ', null);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final note = await db.select(db.notes).getSingle();
      expect(
        decodeNoteContent(note.content).toPlainText(),
        'Note: Self-attention [@vaswani2017] and [@nobody2020].\n',
      );

      // Tapping a chip opens its paper.
      await tester.tap(find.text('(Vaswani et al., 2017)'));
      await tester.pumpAndSettle();
      expect(find.text('Attention Is All You Need'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
