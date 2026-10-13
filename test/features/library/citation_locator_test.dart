import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/csl/csl_format.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/library/citations.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_stats.dart';
import 'package:flutter_quill/flutter_quill.dart';

Paper _paper(String id, String authors, int year, String key) => Paper(
  id: id,
  title: 'Title $id',
  authors: authors,
  year: year,
  venue: 'Journal',
  citekey: key,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('parseCitationGroup', () {
    CiteItem one(String marker) => parseCitationGroup(marker).single;

    test('plain keys have no locator', () {
      expect(one('[@kandel2013]'), const CiteItem('kandel2013'));
    });

    test('labels', () {
      expect(
        one('[@k, p. 42]'),
        const CiteItem('k', locator: '42', label: 'page'),
      );
      expect(one('[@k, pp. 3–5]').label, 'page');
      expect(one('[@k, page 7]').locator, '7');
      expect(one('[@k, pages 7-9]').locator, '7–9');
      expect(one('[@k, chap. 2]').label, 'chapter');
      expect(one('[@k, ch. 2]').label, 'chapter');
      expect(one('[@k, chapter 2]').label, 'chapter');
      expect(one('[@k, sec. 3.1]').label, 'section');
      expect(
        one('[@k, §3]'),
        const CiteItem('k', locator: '3', label: 'section'),
      );
      expect(one('[@k, fig. 4]').label, 'figure');
      expect(one('[@k, para. 5]').label, 'paragraph');
      expect(one('[@k, ¶5]').label, 'paragraph');
      expect(one('[@k, vol. 2]').label, 'volume');
      expect(one('[@k, l. 8]').label, 'line');
      expect(one('[@k, ll. 8-9]').label, 'line');
      expect(one('[@k, n. 3]').label, 'note');
    });

    test('a bare number is a page', () {
      expect(
        one('[@k, 42]'),
        const CiteItem('k', locator: '42', label: 'page'),
      );
      expect(one('[@k, 3-5]').locator, '3–5');
    });

    test('several items each keep their own locator', () {
      final items = parseCitationGroup('[@a, pp. 3–5; @b; @c, chap. 2]');
      expect(items.map((i) => i.key), ['a', 'b', 'c']);
      expect(items[0].locator, '3–5');
      expect(items[1].hasLocator, isFalse);
      expect(items[2].label, 'chapter');
    });

    test('[@?] is not a citation', () {
      expect(parseCitationGroup('[@?]'), isEmpty);
      expect(citedKeys('needs one [@?] here'), isEmpty);
    });

    test('garbled text is a free-text locator without a label', () {
      final i = one('[@k, passim]');
      expect(i.key, 'k');
      expect(i.locator, 'passim');
      expect(i.label, isNull);
      expect(i.display, 'passim');
      expect(one('[@k, p.]').key, 'k');
    });

    test('citedKeys ignores locators', () {
      expect(citedKeys('x [@a, p. 3] y [@b; @a, 4] z [@c, chap. 2]'), [
        'a',
        'b',
        'c',
      ]);
    });

    test('markup round-trips', () {
      for (final m in ['[@a, p. 42]', '[@a, pp. 3–5; @b]', '[@k, chap. 2]']) {
        expect(citationMarkerFor(parseCitationGroup(m)), m);
      }
    });
  });

  group('hand-written styles', () {
    final byKey = {
      'kandel2013': _paper(
        '1',
        'Kandel, Eric; Schwartz, J; Jessell, T',
        2013,
        'kandel2013',
      ),
      'b': _paper('2', 'Smith, Jo', 2019, 'b'),
    };
    String r(String text, CitationStyle s) =>
        replaceCitations(text, byKey, s).text;

    test('APA', () {
      expect(
        r('[@kandel2013, p. 42]', CitationStyle.apa),
        '(Kandel et al., 2013, p. 42)',
      );
      expect(
        r('[@kandel2013, 42]', CitationStyle.apa),
        '(Kandel et al., 2013, p. 42)',
      );
      expect(
        r('[@kandel2013, pp. 3–5]', CitationStyle.apa),
        '(Kandel et al., 2013, pp. 3–5)',
      );
      expect(
        r('[@kandel2013, chap. 2]', CitationStyle.apa),
        '(Kandel et al., 2013, chap. 2)',
      );
      expect(
        r('[@kandel2013, pp. 3–5; @b]', CitationStyle.apa),
        '(Kandel et al., 2013, pp. 3–5; Smith, 2019)',
      );
      expect(r('[@kandel2013]', CitationStyle.apa), '(Kandel et al., 2013)');
    });

    test('MLA', () {
      expect(r('[@b, p. 42]', CitationStyle.mla), '(Smith 42)');
      expect(r('[@b, chap. 2]', CitationStyle.mla), '(Smith, chap. 2)');
    });

    test('IEEE', () {
      expect(
        r('[@kandel2013, p. 42] [@b]', CitationStyle.ieee),
        '[1, p. 42] [2]',
      );
    });

    test('Chicago and Harvard', () {
      for (final s in [CitationStyle.chicago, CitationStyle.harvard]) {
        expect(r('[@b, p. 42]', s), contains('Smith, 2019, p. 42'));
      }
    });
  });

  group('CSL styles', () {
    final byKey = {
      'kandel2013': _paper(
        '1',
        'Kandel, Eric; Schwartz, J; Jessell, T',
        2013,
        'kandel2013',
      ),
      'b': _paper('2', 'Smith, Jo', 2019, 'b'),
    };
    Future<String> cite(CitationStyle s, String text) async {
      final plan = await CslCitationPlan.build([text], byKey, s);
      expect(plan, isNotNull);
      return plan!.replace(text);
    }

    test('APA', () async {
      expect(
        await cite(CitationStyle.apa, '[@b, p. 42]'),
        '(Smith, 2019, p. 42)',
      );
      expect(
        await cite(CitationStyle.apa, '[@b, pp. 3–5]'),
        '(Smith, 2019, pp. 3–5)',
      );
      expect(
        await cite(CitationStyle.apa, '[@b, chap. 2]'),
        '(Smith, 2019, Chapter 2)',
      );
      expect(await cite(CitationStyle.apa, '[@b]'), '(Smith, 2019)');
      expect(
        await cite(CitationStyle.apa, '[@b, 42; @kandel2013, 3]'),
        contains('p. 42'),
      );
    });

    test('IEEE', () async {
      expect(await cite(CitationStyle.ieee, '[@b, p. 42]'), '[1, p. 42]');
      expect(await cite(CitationStyle.ieee, '[@b, pp. 3–5]'), '[1, pp. 3–5]');
      expect(await cite(CitationStyle.ieee, '[@b]'), '[1]');
    });

    test('Chicago author-date', () async {
      expect(
        await cite(CitationStyle.chicago, '[@b, p. 42]'),
        '(Smith 2019, 42)',
      );
      expect(await cite(CitationStyle.chicago, '[@b]'), '(Smith 2019)');
      expect(
        await cite(CitationStyle.chicago, '[@b, chap. 2]'),
        contains('chap. 2'),
      );
    });

    test('Nature has no pinpoints', () async {
      final a = await cite(CitationStyle.nature, '[@b, p. 42]');
      final b = await cite(CitationStyle.nature, '[@b]');
      expect(a, b);
    });

    test('free text without a label still prints', () async {
      expect(await cite(CitationStyle.apa, '[@b, passim]'), contains('passim'));
    });
  });

  group('editor round trip', () {
    test('stored → editor → stored keeps the marker exactly', () {
      final stored = encodeNoteContent(
        Document.fromJson([
          {'insert': 'As shown [@kandel2013, p. 42] and [@a, pp. 3–5; @b].\n'},
        ]),
      );
      final doc = editorDocument(stored);
      expect(jsonEncode(doc.toDelta().toJson()), contains('"cite"'));
      expect(storedFromEditor(doc), stored);
    });

    test('word count ignores a locator', () {
      Document d(String t) => Document.fromJson([
        {'insert': '$t\n'},
      ]);
      expect(
        noteStats(editorDocument(encodeNoteContent(d('See [@a, p. 42] here'))))
            .words,
        2,
      );
      final s = noteStats(d('See [@a, pp. 3–5; @b] here'));
      expect(s.words, 2);
      expect(s.citations, 2);
    });
  });
}
