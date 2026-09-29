import '../../data/database.dart';
import 'authors.dart';

enum CitationStyle {
  apa('APA'),
  mla('MLA'),
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
