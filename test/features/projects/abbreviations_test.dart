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
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/projects/abbreviations.dart';
import 'package:corplex/features/projects/abbreviations_section.dart';
import 'package:corplex/features/projects/projects_providers.dart';

import '../../support/fake_audio_engine.dart';

String body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

Map<String, String> defs(String text) => {
  for (final d in findAbbreviationDefinitions(text)) d.sf: d.longForm,
};

AbbreviationSource src(String id, String text) =>
    AbbreviationSource(noteId: id, title: id, content: body(text));

void main() {
  group('definitions', () {
    test('long form (SF)', () {
      expect(
        defs(
          'We lesioned the medial prefrontal cortex (mPFC) and '
          'long-term potentiation (LTP) was lost; functional magnetic '
          'resonance imaging (fMRI) agreed. The cornu ammonis 1 (CA1) and '
          'ventral tegmental area (VTA) and dentate gyrus (DG) and '
          'brain-derived neurotrophic factor (BDNF) too.',
        ),
        {
          'mPFC': 'medial prefrontal cortex',
          'LTP': 'long-term potentiation',
          'fMRI': 'functional magnetic resonance imaging',
          'CA1': 'cornu ammonis 1',
          'VTA': 'ventral tegmental area',
          'DG': 'dentate gyrus',
          'BDNF': 'brain-derived neurotrophic factor',
        },
      );
    });

    test('SF (long form)', () {
      expect(defs('The mPFC (medial prefrontal cortex) fires.'), {
        'mPFC': 'medial prefrontal cortex',
      });
    });

    test('plural short forms define the singular', () {
      expect(defs('Blocking N-methyl-D-aspartate receptors (NMDARs) helps.'), {
        'NMDAR': 'N-methyl-D-aspartate receptors',
      });
    });

    test('rejects stats, figures, asides and markers', () {
      expect(defs('Groups differed (n = 12) and (p < 0.05) see (Fig. 2).'), {});
      expect(defs('As shown (see above) in the data (n=12).'), {});
      expect(defs('Cells in the region (i.e. the mPFC) responded.'), {});
      expect(defs('Many studies [@smith2020] (LTP) exist.'), {});
      expect(defs(r'We set $a$ (AB) and then $\alpha (LTP)$.'), {});
    });

    test('nested parentheses', () {
      expect(
        defs('Lesions (of the medial prefrontal cortex (mPFC) in rats) hurt.'),
        {'mPFC': 'medial prefrontal cortex'},
      );
      expect(defs('Things (see the dentate gyrus (DG) of the rat) are fine.'), {
        'DG': 'dentate gyrus',
      });
    });

    test('does not cross sentences', () {
      expect(defs('Rats ran. Cortex (PFC) was cut.'), {});
    });
  });

  group('per chapter', () {
    test('flags use before spelling out, per chapter', () {
      final r = analyzeAbbreviations([
        src('a', 'The medial prefrontal cortex (mPFC) matters. mPFC again.'),
        src(
          'b',
          'Here the mPFC is used first. Later medial prefrontal cortex (mPFC).',
        ),
        src('c', 'No abbreviation at all.'),
        src('d', 'Spelled out: medial prefrontal cortex (mPFC) okay.'),
      ]);
      expect(r.defined.single.sf, 'mPFC');
      expect(r.defined.single.noteId, 'a');
      expect(r.chapters.length, 1);
      expect(r.chapters.single.noteId, 'b');
      final i = r.chapters.single.issues.single;
      expect(i.message, "mPFC is used before it's spelled out");
      expect(i.offset, 'Here the '.length);
      expect(r.issueCount, 1);
    });

    test('SF (long form) spelled out at first use is fine', () {
      final r = analyzeAbbreviations([
        src('a', 'The mPFC (medial prefrontal cortex) and mPFC.'),
      ]);
      expect(r.chapters, isEmpty);
    });

    test('offsets count a citation chip as one character', () {
      final stored = jsonEncode([
        {'insert': 'Prefrontal cortex (PFC) is known [@vaswani2017].\n'},
        {'insert': 'x'},
      ]);
      final second = jsonEncode([
        {'insert': 'See [@vaswani2017] and \$x\$ then PFC here.\n'},
      ]);
      final r = analyzeAbbreviations([
        AbbreviationSource(noteId: 'a', title: 'a', content: stored),
        AbbreviationSource(noteId: 'b', title: 'b', content: second),
      ]);
      final issue = r.chapters.single.issues.single;
      final plain = editorDocument(second).toPlainText();
      expect(plain.contains('￼'), isTrue);
      expect(plain.substring(issue.offset, issue.offset + issue.length), 'PFC');
    });

    test('never-defined tokens, with the noise left out', () {
      final r = analyzeAbbreviations([
        src(
          'a',
          'EEG and EEG again, plus GABAergic cells, Figure 2A, stage II, '
              'TODO later, see https://ex.com/ABC and [@DNA2020] and '
              '{#fig:XYZ} and \$QQ\$.\nINTRODUCTION TO THE FIELD\nfMRI too.',
        ),
        src('b', 'More EEG here.'),
      ]);
      final tokens = {for (final u in r.undefined) u.token: u.count};
      expect(tokens, {'EEG': 3, 'fMRI': 1});
      expect(r.undefined.first.token, 'EEG');
      expect(r.undefined.first.noteId, 'a');
      expect(r.isEmpty, isTrue);
    });

    test('long form: most common, ties to the first', () {
      final r = analyzeAbbreviations([
        src('a', 'dorsal raphe nucleus (DRN) one.'),
        src('b', 'dorsal raphe nuclei (DRN) two.'),
        src('c', 'dorsal raphe nuclei (DRN) three.'),
        src('d', 'x'),
      ]);
      expect(r.defined.single.longForm, 'dorsal raphe nuclei');
      expect(r.defined.single.noteId, 'b');
      final tie = analyzeAbbreviations([
        src('a', 'dorsal raphe nucleus (DRN) one.'),
        src('b', 'dorsal raphe nuclei (DRN) two.'),
      ]);
      expect(tie.defined.single.longForm, 'dorsal raphe nucleus');
    });
  });

  group('export', () {
    test('blocks are sorted and bold the short form', () {
      final blocks = abbreviationBlocks([
        body(
          'long-term potentiation (LTP) and medial prefrontal cortex (mPFC) and ventral tegmental area (VTA).',
        ),
      ]);
      expect(blocks.first.kind, BlockKind.heading2);
      expect(blocks.first.text, 'Abbreviations');
      expect(
        [for (final b in blocks.skip(1)) b.runs.first.text],
        ['LTP', 'mPFC', 'VTA'],
      );
      expect(blocks[1].runs.first.bold, isTrue);
      expect(blocks[1].text, 'LTP  long-term potentiation');
    });

    test('empty without definitions', () {
      expect(abbreviationBlocks([body('Nothing, EEG.')]), isEmpty);
    });

    test('copy formats', () {
      const list = [
        DefinedAbbreviation(
          sf: 'DG',
          longForm: 'dentate gyrus',
          noteId: 'a',
          title: 'a',
        ),
      ];
      expect(abbreviationsTsv(list), 'DG\tdentate gyrus');
      expect(abbreviationsMarkdown(list), contains('| DG | dentate gyrus |'));
    });
  });

  group('section', () {
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

    Future<void> addNote(
      String project,
      String id,
      String title,
      String c,
    ) async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(title),
              content: Value(c),
            ),
          );
      await addNoteToProject(db, projectId: project, noteId: id);
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('hidden when empty', (tester) async {
      final p = await findOrCreateProject(db, 'T');
      await addNote(p, 'n1', 'Intro', body('Nothing here, EEG only.'));
      await tester.pumpWidget(
        app(Scaffold(body: ProjectAbbreviationsSection(projectId: p))),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Abbreviations'), findsNothing);
      await dispose(tester);
    });

    testWidgets('shows issues, opens the use selected, lists', (tester) async {
      final p = await findOrCreateProject(db, 'T');
      await addNote(
        p,
        'n1',
        'Intro',
        body('The medial prefrontal cortex (mPFC) matters.'),
      );
      await addNote(
        p,
        'n2',
        'Methods',
        jsonEncode([
          {'insert': 'We read [@a2020] about the mPFC. EEG EEG.\n'},
        ]),
      );
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListView(
              children: [ProjectAbbreviationsSection(projectId: p)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 defined · 1 to check'), findsOneWidget);
      expect(find.text('Methods'), findsOneWidget);
      expect(find.text('Never spelled out (1)'), findsOneWidget);
      expect(find.text('EEG'), findsNothing);

      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(find.text('medial prefrontal cortex'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text("mPFC is used before it's spelled out"));
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      final sel = editor.controller.selection;
      final plain = editor.controller.document.toPlainText();
      expect(plain.substring(sel.start, sel.end), 'mPFC');
      await dispose(tester);
    });
  });
}
