import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_editor_screen.dart';
import 'package:corplex/features/notes/note_stats.dart';
import 'package:corplex/features/notes/paste_citation.dart';
import 'package:corplex/features/settings/appearance_settings.dart';

import '../../support/fake_audio_engine.dart';

String _stored(List<Map<String, Object?>> ops) =>
    encodeNoteContent(Document.fromJson(ops));

const _crossref = {
  'message': {
    'title': ['Deep learning'],
    'author': [
      {'given': 'Yann', 'family': 'LeCun'},
    ],
    'issued': {
      'date-parts': [
        [2015],
      ],
    },
    'container-title': ['Nature'],
    'DOI': '10.1038/nature14539',
  },
};

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            year: const Value(2017),
            venue: const Value('NeurIPS'),
            citekey: const Value('vaswani2017'),
          ),
        );
    for (var i = 1; i <= 4; i++) {
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              paperId: 'p1',
              pageNumber: i,
              quote: 'Quote number $i',
              rectsJson: '[]',
            ),
          );
    }
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<QuillController> open(
    WidgetTester tester,
    String content, {
    MetadataLookup? lookup,
    AppearanceSettings? appearance,
  }) async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('T'),
            content: Value(content),
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          if (lookup != null) metadataLookupProvider.overrideWithValue(lookup),
          if (appearance != null)
            appearanceSettingsProvider.overrideWith((ref) => appearance),
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
    return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('typewriter scrolling', () {
    test('is off by default and persists per device', () async {
      expect((await AppearanceSettings.load()).typewriter, isFalse);
      await AppearanceSettings().setTypewriter(true);
      expect((await AppearanceSettings.load()).typewriter, isTrue);
    });

    testWidgets('the ⋮ menu toggles it', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppearanceSettings();
      await open(tester, '', appearance: settings);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Typewriter scrolling'));
      await tester.pumpAndSettle();
      expect(settings.typewriter, isTrue);
      expect((await AppearanceSettings.load()).typewriter, isTrue);
      await close(tester);
    });

    for (final on in [false, true]) {
      testWidgets('typing at the end ${on ? 'follows' : 'ignores'} the line', (
        tester,
      ) async {
        final lines = List.generate(60, (i) => 'Line $i\n').join();
        final controller = await open(
          tester,
          _stored([
            {'insert': lines},
          ]),
          appearance: AppearanceSettings(typewriter: on),
        );
        final scroll = tester
            .widget<ListView>(find.byType(ListView).first)
            .controller!;
        expect(scroll.offset, 0);
        // Focus the body, then move the caret to the end like typing would.
        await tester.tapAt(
          tester.getTopLeft(find.byType(QuillEditor)) + const Offset(20, 10),
        );
        await tester.pump();
        controller.updateSelection(
          TextSelection.collapsed(offset: controller.document.length - 1),
          ChangeSource.local,
        );
        await tester.pumpAndSettle();
        if (on) {
          expect(scroll.offset, greaterThan(100));
        } else {
          expect(scroll.offset, 0);
        }
        await tester.pump(const Duration(seconds: 1));
        await close(tester);
      });
    }
  });

  group('citation card', () {
    testWidgets('long-press shows details and highlights; tap opens', (
      tester,
    ) async {
      await open(
        tester,
        _stored([
          {'insert': 'See [@vaswani2017] and [@nobody2020].\n'},
        ]),
      );
      await tester.longPress(find.text('(Vaswani & Shazeer, 2017)'));
      await tester.pumpAndSettle();
      expect(find.text('Attention Is All You Need'), findsOneWidget);
      expect(find.text('Ashish Vaswani and Noam Shazeer'), findsOneWidget);
      expect(find.text('2017 · NeurIPS'), findsOneWidget);
      expect(find.textContaining('Quote number 1'), findsOneWidget);
      expect(find.textContaining('Quote number 3'), findsOneWidget);
      expect(find.textContaining('Quote number 4'), findsNothing);
      expect(find.text('Open paper'), findsOneWidget);

      // Tapping outside dismisses.
      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();
      expect(find.text('Open paper'), findsNothing);

      await tester.longPress(find.text('[@nobody2020]'));
      await tester.pumpAndSettle();
      expect(find.text('@nobody2020 isn\'t in your library.'), findsOneWidget);
      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();

      // The chip itself still opens the paper.
      await tester.tap(find.text('(Vaswani & Shazeer, 2017)'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsNothing);
      await close(tester);
    });
  });

  testWidgets('resting a mouse on a chip shows the card, leaving hides it', (
    tester,
  ) async {
    await open(
      tester,
      _stored([
        {'insert': 'See [@vaswani2017].\n'},
      ]),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.text('(Vaswani & Shazeer, 2017)')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Open paper'), findsNothing, reason: 'after a delay');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Open paper'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 590));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Open paper'), findsNothing);
    await close(tester);
  });

  group('word count', () {
    test('counts prose, not chips or sketches', () {
      final doc = Document.fromJson([
        {'insert': 'One two three '},
        {
          'insert': {'cite': '[@a2020; @b2021]'},
        },
        {'insert': ' four.\n\nSecond paragraph\n'},
        {
          'insert': {'sketch': '{}'},
        },
        {'insert': '\n'},
      ]);
      final s = noteStats(doc);
      expect(s.words, 6);
      expect(s.paragraphs, 2);
      expect(s.citations, 2);
      expect(s.characters, 'One two three   four.'.length + 16);
      expect(s.readingMinutes, 1);
      expect(readingTimeLabel(s), '< 1 min');
    });

    testWidgets('⋮ → Word count opens the sheet', (tester) async {
      await open(
        tester,
        _stored([
          {'insert': 'Alpha beta [@vaswani2017].\n'},
        ]),
      );
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Word count'));
      await tester.pumpAndSettle();
      expect(find.text('Words'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('Words')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('Citations')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('Linked papers')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('pasting an identifier', () {
    test('only a whole identifier counts', () {
      expect(wholeIdentifier('10.1038/nature14539'), isNotNull);
      expect(wholeIdentifier('https://doi.org/10.1038/nature14539'), isNotNull);
      expect(wholeIdentifier('arXiv:1706.03762v5'), isNotNull);
      expect(wholeIdentifier('https://arxiv.org/abs/1706.03762'), isNotNull);
      expect(
        wholeIdentifier('https://arxiv.org/pdf/1706.03762v7.pdf'),
        isNotNull,
      );
      expect(wholeIdentifier('see 10.1038/nature14539 for details'), isNull);
      expect(
        wholeIdentifier('https://example.com/10.1038/nature14539'),
        isNull,
      );
      expect(pastedIdentifier('1'), isNull);
      expect(pastedIdentifier('10.1'), isNull);
    });

    MetadataLookup lookupWith(Future<http.Response> Function() answer) =>
        MetadataLookup(client: MockClient((_) => answer()));

    testWidgets('typing never offers; pasting does, and accepting cites', (
      tester,
    ) async {
      final controller = await open(
        tester,
        _stored([
          {'insert': 'Intro: \n'},
        ]),
        lookup: lookupWith(
          () async => http.Response(jsonEncode(_crossref), 200),
        ),
      );
      // Typing character by character: no snackbar.
      for (final ch in '10.1038/nature14539'.split('')) {
        controller.replaceText(controller.document.length - 1, 0, ch, null);
      }
      await tester.pump();
      expect(find.text('Add this paper and cite it?'), findsNothing);
      controller.replaceText(7, 19, '', null);

      // Pasting a sentence: no snackbar.
      controller.replaceText(7, 0, 'see 10.1038/nature14539 now', null);
      await tester.pump();
      expect(find.text('Add this paper and cite it?'), findsNothing);
      controller.replaceText(7, 27, '', null);

      // Pasting the DOI alone: offered.
      controller.replaceText(7, 0, '10.1038/nature14539', null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Add this paper and cite it?'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      final papers = await db.select(db.papers).get();
      final added = papers.singleWhere((p) => p.title == 'Deep learning');
      expect(added.citekey, 'lecun2015');
      expect(
        controller.document.toPlainText().replaceAll('￼', '<chip>'),
        'Intro: <chip> \n',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final note = await db.select(db.notes).getSingle();
      expect(
        decodeNoteContent(note.content).toPlainText(),
        'Intro: [@lecun2015] \n',
      );
      await close(tester);
    });

    testWidgets(
      'a duplicate cites the existing paper; offline changes nothing',
      (tester) async {
        await db
            .update(db.papers)
            .write(const PapersCompanion(doi: Value('10.1038/nature14539')));
        final controller = await open(
          tester,
          _stored([
            {'insert': '\n'},
          ]),
          lookup: lookupWith(
            () async => http.Response(
              jsonEncode({
                'message': {
                  ..._crossref['message']! as Map,
                  'title': ['Attention Is All You Need'],
                  'DOI': '10.1038/nature14539',
                },
              }),
              200,
            ),
          ),
        );
        controller.replaceText(0, 0, '10.1038/nature14539', null);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Add'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        expect(await db.select(db.papers).get(), hasLength(1));
        expect(controller.document.toPlainText(), '￼ \n');
        await close(tester);
      },
    );

    testWidgets('lookup failure leaves the pasted text alone', (tester) async {
      final controller = await open(
        tester,
        _stored([
          {'insert': '\n'},
        ]),
        lookup: lookupWith(() async => throw Exception('offline')),
      );
      controller.replaceText(0, 0, 'arXiv:1706.03762', null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Add'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(controller.document.toPlainText(), 'arXiv:1706.03762\n');
      expect(find.textContaining('Couldn\'t reach'), findsOneWidget);
      await close(tester);
    });
  });
}
