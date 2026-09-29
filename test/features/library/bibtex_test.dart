import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/bibtex.dart';

const _sample = r'''
% a comment line
@string{nips = "Advances in Neural Information Processing Systems"}
@comment{ignored @article{fake, title={No}} }

@inproceedings{vaswani2017,
  title     = {Attention Is All You Need},
  author    = {Vaswani, Ashish and Shazeer, Noam and Parmar, Niki},
  booktitle = nips,
  year      = 2017,
  doi       = {10.5555/3295222.3295349},
}

@article{mueller,
  author  = "M{\"u}ller, J{\"o}rg and Garc{\'\i}a, Ana",
  title   = "{BERT}: Pre-training of {Deep} Bidirectional Transformers",
  journal = {Journal of \& Things},
  year    = {2019},
  url     = {https://doi.org/10.1234/abcd.5678},
}

@book{notitle, author = {Nobody}}
@article{broken, title = {Never closed
''';

Paper _paper(String id, String title, String authors, {String? venue, String? doi}) =>
    Paper(
      id: id,
      title: title,
      authors: authors,
      year: 2017,
      venue: venue,
      doi: doi,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('parses entries, strings, quoting, accents and DOIs', () {
    final papers = parseBibtex(_sample);
    expect(papers.map((p) => p.title), [
      'Attention Is All You Need',
      'BERT: Pre-training of Deep Bidirectional Transformers',
    ]);

    final vaswani = papers[0];
    expect(vaswani.authors, 'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki');
    expect(vaswani.year, 2017);
    expect(vaswani.venue, 'Advances in Neural Information Processing Systems');
    expect(vaswani.doi, '10.5555/3295222.3295349');

    final mueller = papers[1];
    expect(mueller.authors, startsWith('Müller, Jörg; Garc'));
    expect(mueller.venue, 'Journal of & Things');
    expect(mueller.doi, '10.1234/abcd.5678', reason: 'from a doi.org URL');
  });

  test('empty or junk input yields nothing', () {
    expect(parseBibtex(''), isEmpty);
    expect(parseBibtex('just some text @ here'), isEmpty);
  });

  test('export → import round-trips the data', () {
    final papers = [
      _paper('a', 'Attention Is All You Need', 'Vaswani, Ashish; Shazeer, Noam',
          venue: 'NeurIPS', doi: '10.1000/xyz'),
      _paper('b', 'Attention Is Not Explanation', 'Vaswani, Ashish'),
    ];
    final bib = exportBibtex(papers);
    // Same key would collide; the second gets a suffix.
    expect(bib, contains('@article{Vaswani2017Attention,'));
    expect(bib, contains('@article{Vaswani2017Attentionb,'));

    final back = parseBibtex(bib);
    expect(back, hasLength(2));
    expect(back[0].title, papers[0].title);
    expect(back[0].authors, papers[0].authors);
    expect(back[0].venue, 'NeurIPS');
    expect(back[0].doi, '10.1000/xyz');
    expect(back[1].year, 2017);
  });
}
