import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/library/authors.dart';

void main() {
  group('parseAuthors', () {
    test('natural names separated by ; or and', () {
      for (final raw in [
        'Ashish Vaswani; Noam Shazeer',
        'Ashish Vaswani and Noam Shazeer',
        'Ashish Vaswani & Noam Shazeer',
        'Ashish Vaswani\nNoam Shazeer',
      ]) {
        expect(parseAuthors(raw).authors, [
          const Author(family: 'Vaswani', given: 'Ashish'),
          const Author(family: 'Shazeer', given: 'Noam'),
        ], reason: raw);
      }
    });

    test('BibTeX "Family, Given and Family, Given"', () {
      expect(parseAuthors('Vaswani, Ashish and Shazeer, Noam').authors, [
        const Author(family: 'Vaswani', given: 'Ashish'),
        const Author(family: 'Shazeer', given: 'Noam'),
      ]);
    });

    test('a single "Family, Given"', () {
      expect(parseAuthors('Vaswani, Ashish').authors.single, const Author(family: 'Vaswani', given: 'Ashish'));
    });

    test('comma-separated full names, and Family, Given pairs', () {
      expect(parseAuthors('Ashish Vaswani, Noam Shazeer, Niki Parmar').authors.map((a) => a.family), ['Vaswani', 'Shazeer', 'Parmar']);
      expect(parseAuthors('Vaswani, Ashish, Shazeer, Noam').authors.map((a) => a.given), ['Ashish', 'Noam']);
    });

    test('particles stay with the family name', () {
      final a = parseAuthors('Ludwig van der Berg').authors.single;
      expect(a.family, 'van der Berg');
      expect(a.given, 'Ludwig');
    });

    test('et al. is recognised and dropped from the names', () {
      final list = parseAuthors('Vaswani et al.');
      expect(list.etAl, isTrue);
      expect(list.authors.single.family, 'Vaswani');
      expect(parseAuthors('Vaswani, A., and others').etAl, isTrue);
    });

    test('empty input', () {
      expect(parseAuthors('  ').isEmpty, isTrue);
    });
  });

  test('initials handle hyphens and existing initials', () {
    expect(const Author(family: 'X', given: 'Jean-Paul').initials, 'J.-P.');
    expect(const Author(family: 'X', given: 'A. B.').initials, 'A. B.');
    expect(const Author(family: 'X', given: 'Ashish Kumar').initials, 'A. K.');
  });

  group('formatting', () {
    final two = parseAuthors('Ashish Vaswani; Noam Shazeer');
    final three = parseAuthors('Ashish Vaswani; Noam Shazeer; Niki Parmar');

    test('APA', () {
      expect(authorsApa(parseAuthors('Ashish Vaswani')), 'Vaswani, A.');
      expect(authorsApa(two), 'Vaswani, A., & Shazeer, N.');
      expect(authorsApa(three), 'Vaswani, A., Shazeer, N., & Parmar, N.');
      expect(authorsApa(parseAuthors('Vaswani et al.')), 'Vaswani et al.');
    });

    test('MLA', () {
      expect(authorsMla(parseAuthors('Ashish Vaswani')), 'Vaswani, Ashish.');
      expect(authorsMla(two), 'Vaswani, Ashish, and Noam Shazeer.');
      expect(authorsMla(three), 'Vaswani, Ashish, et al.');
    });

    test('BibTeX', () {
      expect(authorsBibtex(two), 'Vaswani, Ashish and Shazeer, Noam');
      expect(authorsBibtex(parseAuthors('Vaswani, Ashish et al.')), 'Vaswani, Ashish and others');
    });

    test('stored form round-trips', () {
      final stored = authorsToStored(three);
      expect(stored, 'Vaswani, Ashish; Shazeer, Noam; Parmar, Niki');
      expect(parseAuthors(stored).authors, three.authors);
    });
  });
}
