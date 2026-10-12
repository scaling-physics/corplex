import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/csl/csl_item.dart';
import 'package:corplex/features/csl/csl_registry.dart';
import 'package:corplex/features/csl/csl_style.dart';
import 'package:corplex/features/export/export_actions.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'csl_support.dart';

Paper _paper(
  String id,
  String title,
  String authors,
  int? year, {
  String? venue,
  String? doi,
  String? key,
}) => Paper(
  id: id,
  title: title,
  authors: authors,
  year: year,
  venue: venue,
  doi: doi,
  citekey: key,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  final a = paper(
    'a',
    'article-journal',
    'Same name one',
    [person('Smith', 'John')],
    year: 2017,
    venue: 'J A',
  );
  final b = paper(
    'b',
    'article-journal',
    'Same name two',
    [person('Smith', 'John')],
    year: 2017,
    venue: 'J B',
  );
  final c = paper(
    'c',
    'article-journal',
    'Other Smith',
    [person('Smith', 'Anna')],
    year: 2017,
    venue: 'J C',
  );

  group('disambiguation', () {
    test('year suffixes follow the bibliography order (2017a / 2017b)', () {
      final out = processorFor('apa').process(
        [b, a],
        clusters: [
          [0],
          [1],
        ],
      );
      // Sorted by title within the same author and year: "one" before "two".
      expect(out.citations[1].plain, '(Smith, 2017a)');
      expect(out.citations[0].plain, '(Smith, 2017b)');
      expect(out.bibliography.map((e) => e.plain), [
        'Smith, J. (2017a). Same name one. J A.',
        'Smith, J. (2017b). Same name two. J B.',
      ]);
    });

    test('different given names are told apart by initials first', () {
      final out = processorFor('apa').process(
        [a, c],
        clusters: [
          [0],
          [1],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(J. Smith, 2017)',
        '(A. Smith, 2017)',
      ]);
    });

    test('a hidden extra author is shown before falling back to a suffix', () {
      final x = paper(
        'x',
        'article-journal',
        'Team X',
        [person('Lee', 'Al'), person('Kim', 'Bo'), person('Ng', 'Cy')],
        year: 2020,
        venue: 'J',
      );
      final y = paper(
        'y',
        'article-journal',
        'Team Y',
        [person('Lee', 'Al'), person('Park', 'Di'), person('Ng', 'Cy')],
        year: 2020,
        venue: 'J',
      );
      final out = processorFor('apa').process(
        [x, y],
        clusters: [
          [0],
          [1],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Lee, Kim, et al., 2020)',
        '(Lee, Park, et al., 2020)',
      ]);
    });
  });

  group('numbered styles', () {
    test('number in order of first citation, ignoring the alphabet', () {
      final out = processorFor('ieee').process(
        [vaswani, journal],
        clusters: [
          [1],
          [0, 1],
        ],
      );
      expect(out.citations.map((e) => e.plain), ['[2]', '[1], [2]']);
      expect(out.bibliography.first.plain, startsWith('[1] A. Vaswani'));
      expect(out.bibliography.last.plain, startsWith('[2] J. P. Smith'));
    });

    test('runs of three or more collapse to a range', () {
      final many = [
        for (var i = 0; i < 4; i++)
          paper('p$i', 'article-journal', 'T$i', [
            person('A$i', 'B'),
          ], year: 2000 + i),
      ];
      final out = processorFor('nlm-citation-sequence').process(
        many,
        clusters: [
          [0, 1, 2, 3],
          [0, 1],
        ],
      );
      expect(out.citations.map((e) => e.plain), ['(1–4)', '(1,2)']);
    });
  });

  group('importing a style', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('csl_test');
      CslRegistry.loadAsset = (p) => File(p).readAsString();
      CslRegistry.customDirectory = () async => dir;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('rejects text that is not a style, calmly', () async {
      await expectLater(
        CslRegistry.importXml('this is not xml'),
        throwsA(
          isA<CslFormatException>().having(
            (e) => e.message,
            'message',
            contains('isn\'t valid XML'),
          ),
        ),
      );
      await expectLater(
        CslRegistry.importXml('<html/>'),
        throwsA(isA<CslFormatException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('rejects a dependent style and one with no bibliography', () async {
      const dependent =
          '<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">'
          '<info><title>T</title><id>x</id>'
          '<link href="p" rel="independent-parent"/></info></style>';
      await expectLater(
        CslRegistry.importXml(dependent),
        throwsA(
          isA<CslFormatException>().having(
            (e) => e.message,
            'message',
            contains('parent'),
          ),
        ),
      );
      const bare =
          '<style xmlns="http://purl.org/net/xbiblio/csl" version="1.0">'
          '<info><title>T</title><id>x</id></info></style>';
      await expectLater(
        CslRegistry.importXml(bare),
        throwsA(isA<CslFormatException>()),
      );
    });

    test('stores a good style and offers it as a CitationStyle', () async {
      final xml = File('assets/csl/nature.csl').readAsStringSync();
      final info = await CslRegistry.importXml(xml);
      expect(info.label, 'Nature');
      expect(File('${dir.path}/${info.name}.csl').existsSync(), isTrue);
      CslRegistry.loadCustom();
      final style = CitationStyle.byName(info.name)!;
      expect(style.custom, isTrue);
      expect(CitationStyle.all, contains(style));
      expect(await style.ensureLoaded(), isNotNull);
      await CslRegistry.removeCustom(info.name);
      expect(CitationStyle.byName(info.name), isNull);
    });
  });

  group('papers as CSL-JSON', () {
    test('type comes from venue and DOI', () {
      expect(
        cslTypeOf(
          _paper('1', 'T', 'A B', 2020, venue: 'Nature', doi: '10.1/x'),
        ),
        'article-journal',
      );
      expect(
        cslTypeOf(_paper('2', 'T', 'A B', 2020, venue: 'Proceedings of ICML')),
        'paper-conference',
      );
      expect(
        cslTypeOf(_paper('3', 'T', 'A B', 2020, venue: 'NeurIPS')),
        'paper-conference',
      );
      expect(
        cslTypeOf(
          _paper('4', 'T', 'A B', 2020, doi: '10.48550/arXiv.1706.03762'),
        ),
        'article',
      );
      expect(cslTypeOf(_paper('5', 'T', 'A B', null)), 'article');
    });

    test('authors are parsed, with particles split off', () {
      final item = paperToCsl(
        _paper('1', 'T', 'Anna van der Berg; Kim Jones', 2018, venue: 'J'),
      );
      expect(item['author'], [
        {'family': 'Berg', 'given': 'Anna', 'non-dropping-particle': 'van der'},
        {'family': 'Jones', 'given': 'Kim'},
      ]);
    });

    test('an arXiv preprint carries its id and link', () {
      final item = paperToCsl(
        _paper(
          '1',
          'T',
          'A B',
          2017,
          venue: 'arXiv:1706.03762',
          doi: '10.48550/arXiv.1706.03762',
        ),
      );
      expect(item['type'], 'article');
      expect(item['number'], 'arXiv:1706.03762');
      expect(item['URL'], 'https://arxiv.org/abs/1706.03762');
    });
  });

  group('inside the app', () {
    setUp(() {
      CslRegistry.loadAsset = (p) => File(p).readAsString();
    });

    test('formatCitation uses CSL once loaded, hand-written before', () async {
      final p = _paper(
        '1',
        'Attention is all you need',
        'Vaswani, Ashish; Shazeer, Noam',
        2017,
        venue: 'NeurIPS',
      );
      final before = formatCitation(p, CitationStyle.vancouver);
      await CitationStyle.vancouver.ensureLoaded();
      final after = formatCitation(p, CitationStyle.vancouver);
      expect(
        after,
        startsWith('Vaswani A, Shazeer N. Attention is all you need.'),
      );
      expect(before, isNot(after));
      // Numbered styles leave the number out of a single reference.
      await CitationStyle.ieee.ensureLoaded();
      expect(formatCitation(p, CitationStyle.ieee), startsWith('A. Vaswani'));
    });

    test('export follows the style: numbers in order of first citation', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      for (final (id, title, authors, key) in [
        ('a', 'Attention is all you need', 'Vaswani, Ashish', 'vaswani2017'),
        ('b', 'BERT', 'Devlin, Jacob', 'devlin2019'),
      ]) {
        await db
            .into(db.papers)
            .insert(
              PapersCompanion.insert(
                id: Value(id),
                title: title,
                authors: Value(authors),
                year: Value(id == 'a' ? 2017 : 2019),
                venue: const Value('NeurIPS'),
                citekey: Value(key),
              ),
            );
      }
      const body =
          '[{"insert":"Second first [@devlin2019], then [@vaswani2017; @devlin2019].\\n"}]';
      final doc = await buildStyledExportDoc(
        db,
        const [ExportNote('N', body)],
        title: 'N',
        style: CitationStyle.ieee,
      );
      final texts = doc.blocks.map((b) => b.text).toList();
      expect(texts.first, 'Second first [1], then [1], [2].');
      expect(texts, contains('References'));
      expect(
        texts[texts.indexOf('References') + 1],
        startsWith('[1] J. Devlin'),
      );
      expect(texts.last, startsWith('[2] A. Vaswani'));
      // Titles keep their italics in the runs.
      expect(doc.blocks.last.runs.any((r) => r.italic), isTrue);

      final apa = await buildStyledExportDoc(
        db,
        const [ExportNote('N', body)],
        title: 'N',
        style: CitationStyle.apa,
      );
      expect(apa.blocks.first.text, contains('(Devlin, 2019)'));
      expect(apa.blocks.first.text, contains('(Devlin, 2019; Vaswani, 2017)'));
    });
  });
}
