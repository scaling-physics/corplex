import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/library/reference_import.dart';

void main() {
  const ris = '''
TY  - JOUR
AU  - Vaswani, Ashish
AU  - Shazeer, Noam
TI  - Attention Is All
  You Need
JO  - NeurIPS
PY  - 2017///
DO  - https://doi.org/10.5555/3295222
ER  -

TY  - BOOK
A1  - Smith, Jo
T1  - A Book
Y1  - 2019/05/01
UR  - https://doi.org/10.1000/xyz
ER  -

TY  - JOUR
AU  - No, Title
ER  -
''';

  test(
    'RIS: authors, wrapped titles, dates, DOIs; skips title-less records',
    () {
      final papers = parseRis(ris);
      expect(papers, hasLength(2));
      expect(papers[0].title, 'Attention Is All You Need');
      expect(papers[0].authors, 'Vaswani, Ashish; Shazeer, Noam');
      expect(papers[0].year, 2017);
      expect(papers[0].venue, 'NeurIPS');
      expect(papers[0].doi, '10.5555/3295222');
      expect(papers[1].year, 2019);
      expect(papers[1].doi, '10.1000/xyz', reason: 'from the URL');
    },
  );

  test('CSL JSON from Zotero', () {
    final papers = parseCslJson('''
[{"title":"Deep Nets","author":[{"family":"Lee","given":"Al"},{"family":"Kim","given":"Bo"}],
  "issued":{"date-parts":[[2021,3]]},"DOI":"10.1/abc","container-title":"Nature"},
 {"title":""}]''');
    expect(papers, hasLength(1));
    expect(papers!.single.authors, 'Lee, Al; Kim, Bo');
    expect(papers.single.year, 2021);
    expect(papers.single.venue, 'Nature');
    expect(parseCslJson('not json'), isNull);
  });

  test('parseReferences sniffs the format', () {
    expect(parseReferences(ris), hasLength(2));
    expect(
      parseReferences('@article{k, title={T}, year={2020}}'),
      hasLength(1),
    );
    expect(parseReferences('[{"title":"J"}]'), hasLength(1));
    expect(parseReferences('nothing here'), isEmpty);
  });
}
