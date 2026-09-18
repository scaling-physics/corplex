import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/citation_formatter.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Paper> makePaper({
    String title = 'Attention Is All You Need',
    String authors = 'Vaswani et al.',
    int? year = 2017,
    String? venue = 'NeurIPS',
    String? doi,
  }) async {
    final id = await db.into(db.papers).insert(
          PapersCompanion.insert(
            title: title,
            authors: Value(authors),
            year: Value(year),
            venue: Value(venue),
            doi: Value(doi),
          ),
        );
    return (db.select(
      db.papers,
    )..where((p) => p.id.equals(id))).getSingle();
  }

  test('APA includes authors, parenthesized year, title, and venue', () async {
    final paper = await makePaper();
    expect(
      formatCitation(paper, CitationStyle.apa),
      'Vaswani et al. (2017). Attention Is All You Need. NeurIPS.',
    );
  });

  test('MLA quotes the title and places year at the end', () async {
    final paper = await makePaper();
    expect(
      formatCitation(paper, CitationStyle.mla),
      'Vaswani et al. "Attention Is All You Need." NeurIPS, 2017.',
    );
  });

  test('BibTeX produces a keyed entry with the available fields', () async {
    final paper = await makePaper(doi: '10.1000/xyz');
    final result = formatCitation(paper, CitationStyle.bibtex);
    expect(result, contains('@article{Vaswani2017Attention,'));
    expect(result, contains('title={Attention Is All You Need},'));
    expect(result, contains('author={Vaswani et al.},'));
    expect(result, contains('journal={NeurIPS},'));
    expect(result, contains('year={2017},'));
    expect(result, contains('doi={10.1000/xyz},'));
  });

  test('missing year falls back to "n.d." in APA/MLA and is omitted from BibTeX', () async {
    final paper = await makePaper(year: null, venue: null);
    expect(
      formatCitation(paper, CitationStyle.apa),
      'Vaswani et al. (n.d.). Attention Is All You Need.',
    );
    expect(formatCitation(paper, CitationStyle.bibtex), isNot(contains('year=')));
  });
}
