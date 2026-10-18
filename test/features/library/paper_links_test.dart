import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/bibtex.dart';
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';
import 'package:corplex/features/library/reference_import.dart';
import 'package:corplex/features/zotero/zotero_mapping.dart';

import '../../support/fake_audio_engine.dart';

const _jats =
    '<jats:title>Abstract</jats:title><jats:p>Memory &amp; sleep '
    '<jats:italic>matter</jats:italic>.</jats:p><jats:p>Second '
    'paragraph.</jats:p>';

String _crossref({bool withAbstract = true}) => jsonEncode({
  'message': {
    'DOI': '10.1000/x',
    'URL': 'http://dx.doi.org/10.1000/x',
    'title': ['A study'],
    'container-title': ['Neuron'],
    'author': [
      {'given': 'Ada', 'family': 'Lovelace'},
    ],
    'issued': {
      'date-parts': [
        [2020],
      ],
    },
    if (withAbstract) 'abstract': _jats,
  },
});

const _efetch = '''<PubmedArticleSet><PubmedArticle><Abstract>
<AbstractText Label="BACKGROUND">Hippocampal <i>replay</i> &amp; sleep.</AbstractText>
<AbstractText Label="RESULTS">It helps.</AbstractText>
</Abstract></PubmedArticle></PubmedArticleSet>''';

String _esummary(String pmid, {String? doi}) => jsonEncode({
  'result': {
    pmid: {
      'title': 'Replay in sleep.',
      'authors': [
        {'name': 'Smith JA'},
      ],
      'pubdate': '2019 Mar',
      'fulljournalname': 'Science',
      'articleids': [
        if (doi != null) {'idtype': 'doi', 'value': doi},
      ],
    },
  },
});

void main() {
  group('lookups fill the new fields', () {
    test('Crossref: URL and JATS abstract as plain paragraphs', () async {
      final meta = parseCrossref(jsonDecode(_crossref()))!;
      expect(meta.url, 'https://doi.org/10.1000/x');
      expect(meta.abstract, 'Memory & sleep matter.\n\nSecond paragraph.');
      expect(
        parseCrossref(jsonDecode(_crossref(withAbstract: false)))!.abstract,
        isNull,
      );
    });

    test('arXiv: abs link and summary', () {
      final meta = parseArxiv('''<feed><entry>
<id>http://arxiv.org/abs/1706.03762v7</id><published>2017-06-12T00:00:00Z</published>
<title>Attention</title><summary>  We propose
 a model. </summary>
<author><name>A B</name></author></entry></feed>''', '1706.03762')!;
      expect(meta.url, 'https://arxiv.org/abs/1706.03762');
      expect(meta.abstract, 'We propose a model.');
    });

    test('PubMed: pmid, abstract from efetch (labelled), url', () async {
      final requests = <Uri>[];
      final client = MockClient((r) async {
        requests.add(r.url);
        if (r.url.path.endsWith('esummary.fcgi')) {
          return http.Response(_esummary('123'), 200);
        }
        if (r.url.path.endsWith('efetch.fcgi')) {
          return http.Response(_efetch, 200);
        }
        return http.Response('', 404);
      });
      final meta = await MetadataLookup(client: client).pubmed('123');
      expect(meta!.pmid, '123');
      expect(meta.url, 'https://pubmed.ncbi.nlm.nih.gov/123/');
      expect(
        meta.abstract,
        'Background: Hippocampal replay & sleep.\n\nResults: It helps.',
      );
      expect(requests.every((u) => u.scheme == 'https'), isTrue);
      expect(
        requests.every((u) => u.queryParameters['tool'] == 'corplex'),
        isTrue,
      );
    });

    test('PubMed with a DOI keeps pmid and gains Crossref details', () async {
      final client = MockClient((r) async {
        if (r.url.host == 'api.crossref.org') {
          return http.Response(_crossref(withAbstract: false), 200);
        }
        if (r.url.path.endsWith('esummary.fcgi')) {
          return http.Response(_esummary('123', doi: '10.1000/x'), 200);
        }
        return http.Response(_efetch, 200);
      });
      final meta = await MetadataLookup(client: client).pubmed('123');
      expect(meta!.pmid, '123');
      expect(meta.url, 'https://doi.org/10.1000/x');
      expect(meta.abstract, startsWith('Background:'));
    });

    test('an efetch failure only loses the abstract', () async {
      final client = MockClient(
        (r) async => r.url.path.endsWith('esummary.fcgi')
            ? http.Response(_esummary('9'), 200)
            : http.Response('', 500),
      );
      final meta = await MetadataLookup(client: client).pubmed('9');
      expect(meta!.title, 'Replay in sleep');
      expect(meta.abstract, isNull);
    });

    test('Zotero: url, abstractNote, PMID from extra', () {
      final meta = paperFromZoteroItem({
        'key': 'K',
        'data': {
          'itemType': 'journalArticle',
          'title': 'T',
          'url': 'https://example.org/paper',
          'abstractNote': 'An abstract.',
          'extra': 'PMID: 4567\nDOI: 10.1/z',
        },
      })!;
      expect(meta.url, 'https://example.org/paper');
      expect(meta.abstract, 'An abstract.');
      expect(meta.pmid, '4567');
    });

    test('BibTeX / RIS / CSL JSON import', () {
      final bib = parseBibtex('''@article{a,
  title={T}, url={https://example.org/p}, pmid={321},
  abstract={First para.

Second {para}.}, doi={10.1/q}}
@article{b, title={U}, eprint={77}, archiveprefix={pubmed},
  url={https://doi.org/10.1234/r}}''');
      expect(bib[0].url, 'https://example.org/p');
      expect(bib[0].pmid, '321');
      expect(bib[0].abstract, 'First para.\n\nSecond para.');
      expect(bib[1].pmid, '77');
      expect(bib[1].url, isNull); // only the DOI's own link
      expect(bib[1].doi, '10.1234/r');

      final ris = parseReferences('''TY  - JOUR
TI  - T
AU  - Smith, Jo
AN  - 555
UR  - https://example.org/r
AB  - Abstract text
  continued.
ER  -
''');
      expect(ris.single.pmid, '555');
      expect(ris.single.url, 'https://example.org/r');
      expect(ris.single.abstract, 'Abstract text continued.');

      final pmUrl = parseReferences(
        'TY  - JOUR\nTI  - T\n'
        'UR  - https://pubmed.ncbi.nlm.nih.gov/999/\nER  -\n',
      );
      expect(pmUrl.single.pmid, '999');

      final csl = parseReferences(
        jsonEncode([
          {
            'title': 'T',
            'URL': 'https://example.org/c',
            'abstract': 'Abs.',
            'PMID': '42',
          },
        ]),
      );
      expect(csl.single.url, 'https://example.org/c');
      expect(csl.single.abstract, 'Abs.');
      expect(csl.single.pmid, '42');
    });
  });

  group('fillMissingMetadata', () {
    late AppDatabase db;
    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() => db.close());

    test('fills only empty fields and never overwrites', () async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p'),
              title: 'T',
              abstract: const Value('Mine'),
            ),
          );
      const meta = PaperMetadata(
        title: 'T',
        pmid: '1',
        url: 'https://x.org',
        abstract: 'Theirs',
      );
      expect(await fillMissingMetadata(db, 'p', meta), isTrue);
      var p = await (db.select(db.papers)).getSingle();
      expect(p.abstract, 'Mine');
      expect(p.pmid, '1');
      expect(p.url, 'https://x.org');
      const other = PaperMetadata(title: 'T', pmid: '2', url: 'https://y.org');
      expect(await fillMissingMetadata(db, 'p', other), isFalse);
      p = await (db.select(db.papers)).getSingle();
      expect(p.pmid, '1');
      expect(p.url, 'https://x.org');
    });

    test('adding a paper stores them; BibTeX export writes them', () async {
      await addPaperFromMetadata(
        db,
        const PaperMetadata(
          title: 'T',
          authors: 'Doe, Jo',
          year: 2020,
          pmid: '5',
          url: 'https://x.org',
          abstract: 'Words {here}.',
        ),
        id: 'n',
      );
      final bib = exportBibtex(await db.select(db.papers).get());
      expect(bib, contains('pmid={5}'));
      expect(bib, contains('url={https://x.org}'));
      expect(bib, contains('abstract={Words here.}'));
      final back = parseBibtex(bib).single;
      expect(back.pmid, '5');
      expect(back.url, 'https://x.org');
      expect(back.abstract, 'Words here.');
    });
  });

  group('paper screen', () {
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

    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            audioEngineProvider.overrideWithValue(FakeAudioEngine()),
            coverRendererProvider.overrideWithValue((_) async => null),
          ],
          child: const MaterialApp(home: PaperDetailScreen(paperId: 'p1')),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('nothing extra without them', (tester) async {
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p1'), title: 'T'));
      await show(tester);
      expect(find.text('Abstract'), findsNothing);
      expect(find.text('PubMed ID'), findsNothing);
      expect(find.text('Link'), findsNothing);
      await close(tester);
    });

    testWidgets('shows abstract, PMID and link; edits save', (tester) async {
      final long = List.filled(40, 'neurons fire together').join(' ');
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'T',
              abstract: Value(long),
              pmid: const Value('123'),
              url: const Value('https://example.org/p'),
            ),
          );
      await show(tester);
      expect(find.text('Abstract'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.widgetWithText(TextField, '123'), findsOneWidget);
      expect(find.text('https://example.org/p'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '123'), '456');
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Less'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, long),
        'Short abstract',
      );
      await tester.pump(const Duration(seconds: 1));
      final p = await db.select(db.papers).getSingle();
      expect(p.pmid, '456');
      expect(p.abstract, 'Short abstract');
      await close(tester);
    });

    testWidgets('an outside fill appears in untouched fields', (tester) async {
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p1'), title: 'T'));
      await show(tester);
      await (db.update(db.papers)..where((p) => p.id.equals('p1'))).write(
        const PapersCompanion(abstract: Value('Filled by lookup')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abstract'), findsOneWidget);
      expect(find.text('Filled by lookup'), findsOneWidget);
      await close(tester);
    });
  });
}
