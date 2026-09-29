import '../../data/database.dart';
import 'authors.dart';

enum CitationStyle {
  apa('APA'),
  mla('MLA'),
  chicago('Chicago'),
  harvard('Harvard'),
  ieee('IEEE'),
  bibtex('BibTeX');

  const CitationStyle(this.label);

  final String label;
}

String formatCitation(Paper paper, CitationStyle style) {
  final list = parseAuthors(paper.authors);
  final title = paper.title.trim();
  final venue = paper.venue?.trim() ?? '';
  final year = paper.year?.toString() ?? 'n.d.';

  switch (style) {
    case CitationStyle.apa:
      final buffer = StringBuffer();
      final apa = authorsApa(list);
      if (apa.isNotEmpty) buffer.write('$apa ');
      buffer.write('($year). $title.');
      if (venue.isNotEmpty) buffer.write(' $venue.');
      return buffer.toString().trim();

    case CitationStyle.mla:
      final buffer = StringBuffer();
      final mla = authorsMla(list);
      if (mla.isNotEmpty) buffer.write('$mla ');
      buffer.write('"$title."');
      if (venue.isNotEmpty) buffer.write(' $venue,');
      buffer.write(' $year.');
      return buffer.toString().trim();

    case CitationStyle.chicago:
      // Chicago author-date: Family, Given, and Given Family. Year. "Title." Venue.
      final buffer = StringBuffer();
      final names = _chicagoAuthors(list);
      if (names.isNotEmpty) buffer.write('$names. ');
      buffer.write('$year. "$title."');
      if (venue.isNotEmpty) buffer.write(' $venue.');
      return buffer.toString().trim();

    case CitationStyle.harvard:
      // Harvard: Family, I., Family, I. and Family, I. (Year) 'Title', Venue.
      final names = [
        for (final a in list.authors)
          a.given.isEmpty ? a.family : '${a.family}, ${a.initials}',
      ];
      final who = names.isEmpty
          ? ''
          : list.etAl
          ? '${names.join(', ')} et al.'
          : names.length == 1
          ? names.single
          : '${names.take(names.length - 1).join(', ')} and ${names.last}';
      final buffer = StringBuffer();
      if (who.isNotEmpty) buffer.write('$who ');
      buffer.write("($year) '$title'");
      buffer.write(venue.isNotEmpty ? ', $venue.' : '.');
      return buffer.toString().trim();

    case CitationStyle.ieee:
      // IEEE: I. Family, I. Family, and I. Family, "Title," Venue, Year.
      final names = [
        for (final a in list.authors)
          a.given.isEmpty ? a.family : '${a.initials} ${a.family}',
      ];
      final who = names.isEmpty
          ? ''
          : list.etAl || names.length > 6
          ? '${names.first} et al.'
          : names.length == 1
          ? names.single
          : names.length == 2
          ? '${names[0]} and ${names[1]}'
          : '${names.take(names.length - 1).join(', ')}, and ${names.last}';
      final buffer = StringBuffer();
      if (who.isNotEmpty) buffer.write('$who, ');
      buffer.write('"$title,"');
      if (venue.isNotEmpty) buffer.write(' $venue,');
      buffer.write(' ${paper.year ?? 'n.d.'}.');
      return buffer.toString().trim();

    case CitationStyle.bibtex:
      final lines = <String>['@article{${bibtexKey(paper)},'];
      lines.add('  title={$title},');
      if (!list.isEmpty) lines.add('  author={${authorsBibtex(list)}},');
      if (venue.isNotEmpty) lines.add('  journal={$venue},');
      if (paper.year != null) lines.add('  year={$year},');
      if ((paper.doi ?? '').isNotEmpty) lines.add('  doi={${paper.doi}},');
      lines.add('}');
      return lines.join('\n');
  }
}

/// `Vaswani2017Attention`: first author's family name, year, first word of
/// the title — stable, readable and unlikely to collide.
String bibtexKey(Paper paper) {
  final authors = parseAuthors(paper.authors).authors;
  final firstAuthorWord = authors.isEmpty
      ? 'paper'
      : authors.first.family.split(' ').last;
  final firstTitleWord = paper.title
      .split(' ')
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final year = paper.year?.toString() ?? '';
  return '$firstAuthorWord$year$firstTitleWord'.replaceAll(
    RegExp(r'[^A-Za-z0-9]'),
    '',
  );
}

/// Chicago author-date: first author inverted, the rest natural order.
String _chicagoAuthors(AuthorList list) {
  final a = list.authors;
  if (a.isEmpty) return '';
  final names = [a.first.inverted, ...a.skip(1).map((x) => x.natural)];
  String joined;
  if (list.etAl || a.length > 10) {
    joined =
        '${names.take(a.length > 10 ? 7 : names.length).join(', ')}, et al';
  } else if (names.length == 1) {
    joined = names.single;
  } else if (names.length == 2) {
    joined = '${names[0]}, and ${names[1]}';
  } else {
    joined = '${names.take(names.length - 1).join(', ')}, and ${names.last}';
  }
  return joined;
}
