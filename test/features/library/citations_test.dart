import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/library/citations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  Future<Paper> add(
    String id,
    String title, {
    String authors = '',
    int? year,
    String? venue,
  }) async {
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: Value(id),
            title: title,
            authors: Value(authors),
            year: Value(year),
            venue: Value(venue),
          ),
        );
    return (db.select(db.papers)..where((p) => p.id.equals(id))).getSingle();
  }

  test('citekeys: family + year, ASCII, with fallbacks', () async {
    expect(
      citekeyBase(
        await add('a', 'Attention', authors: 'Vaswani, Ashish', year: 2017),
      ),
      'vaswani2017',
    );
    expect(
      citekeyBase(
        await add('b', 'Über Alles', authors: 'Müller, Jörg', year: 2020),
      ),
      'muller2020',
    );
    expect(citekeyBase(await add('c', 'Deep Learning Survey')), 'deep');
    expect(citekeyBase(await add('d', 'A B')), 'paper');
  });

  test('a citekey is assigned once, made unique, and never changes', () async {
    await add('p1', 'One', authors: 'Smith, Jo', year: 2020);
    await add('p2', 'Two', authors: 'Smith, Al', year: 2020);
    final k1 = await ensureCitekey(db, 'p1');
    final k2 = await ensureCitekey(db, 'p2');
    expect(k1, 'smith2020');
    expect(k2, 'smith2020a');

    await (db.update(db.papers)..where((p) => p.id.equals('p1'))).write(
      const PapersCompanion(year: Value(1999), authors: Value('Jones, X')),
    );
    expect(await ensureCitekey(db, 'p1'), 'smith2020');
  });

  test('citedKeys finds single and grouped citations in order, once', () {
    expect(
      citedKeys('See [@a2017] and [@b2019; @a2017], not [@] or [@bad key!].'),
      ['a2017', 'b2019'],
    );
  });

  test('in-text citations follow the style', () async {
    final one = await add('p', 'T', authors: 'Smith, Jo', year: 2020);
    final two = await add('q', 'T', authors: 'Smith, Jo; Lee, Al', year: 2019);
    final many = await add(
      'r',
      'T',
      authors: 'Smith, Jo; Lee, Al; Kim, Bo',
      year: 2018,
    );
    expect(inTextCitation(one, CitationStyle.apa), '(Smith, 2020)');
    expect(inTextCitation(two, CitationStyle.apa), '(Smith & Lee, 2019)');
    expect(inTextCitation(two, CitationStyle.harvard), '(Smith and Lee, 2019)');
    expect(inTextCitation(many, CitationStyle.chicago), '(Smith et al., 2018)');
    expect(inTextCitation(one, CitationStyle.mla), '(Smith)');
  });

  test('replaceCitations resolves known keys, keeps unknown ones, lists cited', () async {
    final a = await add('a', 'Alpha', authors: 'Smith, Jo', year: 2020);
    final b = await add('b', 'Beta', authors: 'Lee, Al', year: 2019);
    final byKey = {'smith2020': a, 'lee2019': b};

    final apa = replaceCitations(
      'Known [@smith2020], grouped [@smith2020; @lee2019], unknown [@nope].',
      byKey,
      CitationStyle.apa,
    );
    expect(
      apa.text,
      'Known (Smith, 2020), grouped (Smith, 2020; Lee, 2019), unknown [@nope].',
    );
    expect(apa.cited, [a, b]);

    final ieee = replaceCitations(
      'x [@lee2019] y [@smith2020] z [@lee2019]',
      byKey,
      CitationStyle.ieee,
    );
    expect(ieee.text, 'x [1] y [2] z [1]');
    expect(
      referenceList(ieee.cited, CitationStyle.ieee).first,
      startsWith('[1] '),
    );
  });

  test('reference lists are alphabetical, and every style formats', () async {
    final z = await add(
      'z',
      'Zed',
      authors: 'Zhang, Wei',
      year: 2021,
      venue: 'Nature',
    );
    final a = await add(
      'a',
      'Alpha',
      authors: 'Adams, Bo',
      year: 2020,
      venue: 'Science',
    );
    final list = referenceList([z, a], CitationStyle.apa);
    expect(list.first, startsWith('Adams'));
    for (final style in CitationStyle.values) {
      expect(formatCitation(a, style), contains('Alpha'));
    }
    expect(
      formatCitation(a, CitationStyle.ieee),
      'B. Adams, "Alpha," Science, 2020.',
    );
    expect(
      formatCitation(a, CitationStyle.harvard),
      "Adams, B. (2020) 'Alpha', Science.",
    );
    expect(
      formatCitation(a, CitationStyle.chicago),
      'Adams, Bo. 2020. "Alpha." Science.',
    );
  });
}
