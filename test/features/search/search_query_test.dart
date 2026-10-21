import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:corplex/features/search/search_index.dart' show SearchKind;
import 'package:corplex/features/search/search_query.dart';

List<String> words(SearchQuery q) => [for (final t in q.terms) t.toString()];

void main() {
  group('parseSearchQuery', () {
    test('plain words become prefix terms, lowercased', () {
      final q = parseSearchQuery('  Self-Attention  Heads ');
      expect(words(q), ['self', 'attention', 'heads']);
      expect(q.ftsMatch, '"self"* "attention"* "heads"*');
      expect(q.filters, isEmpty);
    });

    test('phrases and exclusions', () {
      final q = parseSearchQuery('"deep  learning" -noise -"white noise" x');
      expect(q.terms, [
        const SearchTerm(['deep', 'learning'], phrase: true),
        const SearchTerm(['noise'], negated: true),
        const SearchTerm(['white', 'noise'], phrase: true, negated: true),
        const SearchTerm(['x']),
      ]);
      expect(
        q.ftsMatch,
        '("deep learning" "x"*) NOT (("noise"*) OR ("white noise"))',
      );
    });

    test('operators', () {
      final q = parseSearchQuery(
        'cortex tag:ml folder:Lab path:Inbox project:Thesis '
        'in:notes in:pdfs is:pinned is:template is:daily',
      );
      expect(words(q), ['cortex']);
      expect(q.filters, const [
        SearchFilter(SearchField.tag, 'ml'),
        SearchFilter(SearchField.folder, 'lab'),
        SearchFilter(SearchField.folder, 'inbox'),
        SearchFilter(SearchField.project, 'thesis'),
        SearchFilter(SearchField.isPinned, ''),
        SearchFilter(SearchField.isTemplate, ''),
        SearchFilter(SearchField.isDaily, ''),
      ]);
      expect(q.kinds, {SearchKind.note, SearchKind.pdfText});
      expect(q.allowsKind(SearchKind.paper), isFalse);
      expect(q.allowsKind(SearchKind.note), isTrue);
    });

    test('negated operators, quoted values, case-insensitive names', () {
      final q = parseSearchQuery(
        'TAG:"Deep Learning" -tag:old -Is:Pinned -in:highlights Folder:"A / B"',
      );
      expect(q.filters, const [
        SearchFilter(SearchField.tag, 'deep learning'),
        SearchFilter(SearchField.tag, 'old', negated: true),
        SearchFilter(SearchField.isPinned, '', negated: true),
        SearchFilter(SearchField.folder, 'a / b'),
      ]);
      expect(q.excludedKinds, {SearchKind.highlight});
      expect(q.allowsKind(SearchKind.highlight), isFalse);
      expect(q.terms, isEmpty);
    });

    test('a leading # on a tag is dropped', () {
      expect(
        parseSearchQuery('tag:#ml').filters.single,
        const SearchFilter(SearchField.tag, 'ml'),
      );
    });

    test('unknown operators and values are plain words', () {
      expect(words(parseSearchQuery('foo:bar')), ['foo', 'bar']);
      expect(words(parseSearchQuery('in:everything')), ['in', 'everything']);
      expect(words(parseSearchQuery('is:happy')), ['is', 'happy']);
      expect(parseSearchQuery('foo:bar').filters, isEmpty);
    });

    test('an operator with no value is ignored', () {
      final q = parseSearchQuery('tag: hello');
      expect(words(q), ['hello']);
      expect(q.filters, isEmpty);
      expect(parseSearchQuery('tag:').isEmpty, isTrue);
    });

    test('blank and punctuation-only input is empty', () {
      for (final s in ['', '   ', '-', '--', '"', '""', '* ^ ( )', '- -']) {
        expect(parseSearchQuery(s).isEmpty, isTrue, reason: '"$s"');
        expect(parseSearchQuery(s).ftsMatch, isNull);
      }
    });

    test('filter- and exclusion-only queries have no FTS string', () {
      expect(parseSearchQuery('tag:x').ftsMatch, isNull);
      expect(parseSearchQuery('-word').ftsMatch, isNull);
      expect(parseSearchQuery('-word').hasPositiveTerms, isFalse);
    });

    test('plainText is the positive words, for in-document Find', () {
      expect(
        parseSearchQuery('"deep learning" tag:x -noise cortex').plainText,
        'deep learning cortex',
      );
    });

    test('matchesText', () {
      final q = parseSearchQuery('"deep learning" -noise');
      expect(q.matchesText('Notes', 'About deep learning today'), isTrue);
      expect(q.matchesText('Notes', 'deep and learning'), isFalse);
      expect(q.matchesText('Notes', 'deep learning with noise'), isFalse);
      expect(parseSearchQuery('att').matchesText('', 'Attention'), isTrue);
    });
  });

  group('FTS strings never raise a syntax error', () {
    final hostile = [
      '"',
      '"unbalanced',
      'unbalanced"',
      '-',
      'NOT',
      'a NOT b',
      'a AND b OR c',
      '*',
      'a*',
      '^start',
      '(a',
      'a)',
      '((a OR b) NEAR c)',
      'title:foo',
      '"a" "b',
      'a -',
      "it's",
      'x\' OR 1=1 --',
      'NEAR(a b)',
      '{a b}',
      '- -a -',
      '"" "" a',
      r'back\slash',
      'tag:"unterminated',
      'tag:x -tag: "q',
      'ünïcode 日本語',
      '-"x" -"y z" -w q',
    ];

    test('every hostile string MATCHes cleanly', () {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute('CREATE VIRTUAL TABLE t USING fts5(title, body)');
      db.execute("INSERT INTO t VALUES ('a b c', 'x y z')");
      for (final input in hostile) {
        final match = parseSearchQuery(input).ftsMatch;
        if (match == null) continue;
        expect(
          () => db.select('SELECT * FROM t WHERE t MATCH ?', [match]),
          returnsNormally,
          reason: '"$input" -> $match',
        );
      }
    });

    test('negation and phrases behave as intended in SQLite', () {
      final db = sqlite.sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute('CREATE VIRTUAL TABLE t USING fts5(title, body)');
      db.execute("INSERT INTO t VALUES ('one', 'deep learning of noise')");
      db.execute("INSERT INTO t VALUES ('two', 'deep learning, quiet')");
      db.execute("INSERT INTO t VALUES ('three', 'learning about deep sea')");
      List<String> run(String q) => [
        for (final r in db.select('SELECT title FROM t WHERE t MATCH ?', [
          parseSearchQuery(q).ftsMatch,
        ]))
          r['title'] as String,
      ]..sort();
      expect(run('deep learning'), ['one', 'three', 'two']);
      expect(run('"deep learning"'), ['one', 'two']);
      expect(run('deep learning -noise'), ['three', 'two']);
      expect(run('deep -noise -sea'), ['two']);
      expect(run('"learn"'), isEmpty); // a phrase is not a prefix
      expect(run('lear'), ['one', 'three', 'two']);
    });
  });
}
