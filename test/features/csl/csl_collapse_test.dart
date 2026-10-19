import 'dart:io';

import 'package:corplex/features/csl/csl_processor.dart';
import 'package:corplex/features/csl/csl_style.dart';
import 'package:flutter_test/flutter_test.dart';

import 'csl_support.dart';

CslProcessor _variant(String file, String from, String to) {
  final xml = File('assets/csl/$file.csl').readAsStringSync();
  expect(xml, contains(from));
  return CslProcessor(CslStyle.parse(xml.replaceFirst(from, to), testLocale()));
}

/// [file] with the sort removed from its citation, so cites keep the order
/// they were given in.
CslProcessor _unsorted(String file) {
  final xml = File('assets/csl/$file.csl').readAsStringSync();
  final at = xml.indexOf('<citation');
  final from = xml.indexOf('<sort>', at);
  final to = xml.indexOf('</sort>', from) + '</sort>'.length;
  return CslProcessor(
    CslStyle.parse(xml.replaceRange(from, to, ''), testLocale()),
  );
}

void main() {
  final smith1 = byAuthor('s1', 'Smith', 2019, 'Alpha study');
  final smith2 = byAuthor('s2', 'Smith', 2019, 'Beta study');
  final smith3 = byAuthor('s3', 'Smith', 2019, 'Delta study');
  final smith4 = byAuthor('s4', 'Smith', 2019, 'Epsilon study');
  final smith5 = byAuthor('s5', 'Smith', 2021, 'Zeta study');
  final jones = byAuthor('j', 'Jones', 2020, 'Gamma study');

  group('collapse by year', () {
    test('APA: one author, years and suffixes together', () {
      final out = processorFor('apa').process(
        [smith1, smith2, jones, smith5],
        clusters: [
          [0, 1, 2, 3],
        ],
      );
      expect(
        out.citations.single.plain,
        '(Jones, 2020; Smith, 2019a, 2019b, 2021)',
      );
    });

    test('cites by the same author are moved together', () {
      final out = _unsorted('elsevier-harvard').process(
        [smith1, jones, smith2],
        clusters: [
          [0, 1, 2],
        ],
      );
      expect(out.citations.single.plain, '(Smith, 2019a, 2019b; Jones, 2020)');
    });

    test('a different author is not collapsed into', () {
      final out = processorFor('apa').process(
        [smith1, jones],
        clusters: [
          [0, 1],
        ],
      );
      expect(out.citations.single.plain, '(Jones, 2020; Smith, 2019)');
    });

    test('a cite with a page of its own stays whole', () {
      final out = processorFor('apa').process(
        [smith1, smith2],
        cites: [
          [const CslCite(0, locator: '42'), const CslCite(1)],
        ],
      );
      expect(out.citations.single.plain, '(Smith, 2019a, p. 42; Smith, 2019b)');
    });

    test('year-suffix prints only the suffix when the year repeats', () {
      final p = _variant('apa', 'collapse="year"', 'collapse="year-suffix"');
      final out = p.process(
        [smith1, smith2, smith3, jones, smith5],
        clusters: [
          [0, 1, 2, 3, 4],
        ],
      );
      expect(
        out.citations.single.plain,
        '(Jones, 2020; Smith, 2019a, b, c, 2021)',
      );
    });

    test('year-suffix-ranged joins three or more in a row', () {
      final p = _variant(
        'apa',
        'collapse="year"',
        'collapse="year-suffix-ranged"',
      );
      final four = p.process(
        [smith1, smith2, smith3, smith4],
        clusters: [
          [0, 1, 2, 3],
          [0, 1],
          [0, 2, 3],
        ],
      );
      expect(four.citations.map((e) => e.plain), [
        '(Smith, 2019a–d)',
        '(Smith, 2019a, b)',
        '(Smith, 2019a, c, d)',
      ]);
    });

    test('the delimiters come from the style', () {
      final xml = File('assets/csl/elsevier-harvard.csl').readAsStringSync();
      final p = CslProcessor(
        CslStyle.parse(
          xml
              .replaceFirst(
                'cite-group-delimiter=", "',
                'cite-group-delimiter=" / " after-collapse-delimiter=" | "',
              )
              .replaceFirst(RegExp(r'<sort>.*?</sort>', dotAll: true), ''),
          testLocale(),
        ),
      );
      final out = p.process(
        [smith1, smith2, jones],
        clusters: [
          [0, 1, 2],
        ],
      );
      expect(
        out.citations.single.plain,
        '(Smith, 2019a / 2019b | Jones, 2020)',
      );
    });
  });

  group('citation numbers', () {
    final many = [
      for (var i = 0; i < 5; i++)
        paper('p$i', 'article-journal', 'T$i', [
          person('A$i', 'B'),
        ], year: 2000 + i),
    ];

    test('NLM: three or more in a row become a range', () {
      final out = processorFor('nlm-citation-sequence').process(
        many,
        clusters: [
          [0, 1, 2, 3, 4],
          [0, 1, 3],
          [0, 1, 2, 4],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(1–5)',
        '(1,2,4)',
        '(1–3,5)',
      ]);
    });

    test('IEEE with collapse: [1]–[3]', () {
      final p = _variant(
        'ieee',
        '<citation>',
        '<citation collapse="citation-number">',
      );
      final out = p.process(
        many,
        clusters: [
          [0, 1, 2],
          [0, 2, 3],
        ],
      );
      expect(out.citations.map((e) => e.plain), ['[1]–[3]', '[1], [3], [4]']);
    });
  });

  group('year suffixes', () {
    test('follow bibliography order, in citations and the list alike', () {
      // Cited in the opposite order to the alphabet of titles.
      final out = processorFor('apa').process(
        [smith3, smith1, smith2],
        clusters: [
          [0],
          [1],
          [2],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Smith, 2019c)',
        '(Smith, 2019a)',
        '(Smith, 2019b)',
      ]);
      expect(out.bibliography.map((e) => e.plain.substring(0, 20)), [
        'Smith, A. (2019a). A',
        'Smith, A. (2019b). B',
        'Smith, A. (2019c). D',
      ]);
    });

    test('run past z into aa, ab', () {
      final lots = [
        for (var i = 0; i < 28; i++)
          byAuthor(
            'x$i',
            'Smith',
            2019,
            'Title ${i.toString().padLeft(2, '0')}',
          ),
      ];
      final out = processorFor('apa').process(
        lots,
        clusters: [
          [26],
          [27],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Smith, 2019aa)',
        '(Smith, 2019ab)',
      ]);
    });

    test('an item already told apart gets none', () {
      final out = processorFor('apa').process(
        [smith1, smith2, jones],
        clusters: [
          [0],
          [2],
        ],
      );
      expect(out.citations.map((e) => e.plain), [
        '(Smith, 2019a)',
        '(Jones, 2020)',
      ]);
    });

    test(
      'extra names tell apart same-year cites before a suffix is needed',
      () {
        final a = paper('a', 'article-journal', 'One', [
          person('Kim', 'Ann'),
          person('Lee', 'Bo'),
          person('Park', 'Cy'),
        ], year: 2018);
        final b = paper('b', 'article-journal', 'Two', [
          person('Kim', 'Ann'),
          person('Wu', 'Di'),
          person('Park', 'Cy'),
        ], year: 2018);
        final out = processorFor('apa').process(
          [a, b],
          clusters: [
            [0],
            [1],
          ],
        );
        expect(out.citations.map((e) => e.plain), [
          '(Kim, Lee, et al., 2018)',
          '(Kim, Wu, et al., 2018)',
        ]);
      },
    );
  });

  group('subsequent-author-substitute', () {
    final two = byAuthor('t', 'Smith', 2018, 'Beta');
    final one = byAuthor('o', 'Smith', 2019, 'Alpha');
    final other = byAuthor('p', 'Jones', 2020, 'Gamma');
    final pair1 = paper(
      'q1',
      'article-journal',
      'First',
      [person('Smith', 'Alex'), person('Jones', 'Kim')],
      year: 2017,
      venue: 'J',
    );
    final pair2 = paper(
      'q2',
      'article-journal',
      'Second',
      [person('Smith', 'Alex'), person('Jones', 'Kim')],
      year: 2018,
      venue: 'J',
    );
    final pair3 = paper(
      'q3',
      'article-journal',
      'Third',
      [person('Smith', 'Alex'), person('Wu', 'Di')],
      year: 2019,
      venue: 'J',
    );

    test('MLA: three dashes for the same author, not for a new one', () {
      final out = processorFor('modern-language-association')
          .process([one, two, other]);
      expect(out.bibliography.map((e) => e.plain), [
        'Jones, Alex. “Gamma.” Journal of Tests, 2020.',
        'Smith, Alex. “Alpha.” Journal of Tests, 2019.',
        '———. “Beta.” Journal of Tests, 2018.',
      ]);
    });

    test('rules: complete-each, partial-each and partial-first', () {
      String run(String rule) {
        final p = _variant(
          'modern-language-association',
          'subsequent-author-substitute="&#8212;&#8212;&#8212;"',
          'subsequent-author-substitute="&#8212;&#8212;&#8212;" '
              'subsequent-author-substitute-rule="$rule"',
        );
        final out = p.process([pair1, pair2, pair3]);
        return out.bibliography
            .map((e) => e.plain.split('. “').first)
            .join(' | ');
      }

      final all = run('complete-all');
      expect(all, startsWith('Smith, Alex, and Kim Jones | ———'));
      expect(all, endsWith('| Smith, Alex, and Di Wu'));
      expect(run('complete-each'), contains('| ———, and ———'));
      expect(run('partial-each'), contains('| ———, and ———'));
      expect(run('partial-each'), endsWith('| ———, and Di Wu'));
      expect(run('partial-first'), endsWith('| ———, and Di Wu'));
    });

    test('a style without it prints every author', () {
      final out = processorFor('apa').process([one, two]);
      expect(out.bibliography.map((e) => e.plain.substring(0, 11)), [
        'Smith, A. (',
        'Smith, A. (',
      ]);
    });
  });
}
