import '../../data/database.dart';

enum CitationStyle {
  apa('APA'),
  mla('MLA'),
  bibtex('BibTeX');

  const CitationStyle(this.label);

  final String label;
}

String formatCitation(Paper paper, CitationStyle style) {
  final authors = paper.authors.trim();
  final title = paper.title.trim();
  final venue = paper.venue?.trim() ?? '';
  final year = paper.year?.toString() ?? 'n.d.';

  switch (style) {
    case CitationStyle.apa:
      final buffer = StringBuffer();
      if (authors.isNotEmpty) buffer.write('$authors ');
      buffer.write('($year). $title.');
      if (venue.isNotEmpty) buffer.write(' $venue.');
      return buffer.toString().trim();

    case CitationStyle.mla:
      final buffer = StringBuffer();
      if (authors.isNotEmpty) {
        buffer.write(authors);
        if (!authors.endsWith('.')) buffer.write('.');
        buffer.write(' ');
      }
      buffer.write('"$title."');
      if (venue.isNotEmpty) buffer.write(' $venue,');
      buffer.write(' $year.');
      return buffer.toString().trim();

    case CitationStyle.bibtex:
      final lines = <String>['@article{${_bibtexKey(paper)},'];
      lines.add('  title={$title},');
      if (authors.isNotEmpty) lines.add('  author={$authors},');
      if (venue.isNotEmpty) lines.add('  journal={$venue},');
      if (paper.year != null) lines.add('  year={$year},');
      if ((paper.doi ?? '').isNotEmpty) lines.add('  doi={${paper.doi}},');
      lines.add('}');
      return lines.join('\n');
  }
}

String _bibtexKey(Paper paper) {
  final firstAuthorWord = paper.authors
      .split(RegExp(r'[ ,]+'))
      .firstWhere((s) => s.isNotEmpty, orElse: () => 'paper');
  final firstTitleWord = paper.title
      .split(' ')
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final year = paper.year?.toString() ?? '';
  return '$firstAuthorWord$year$firstTitleWord'.replaceAll(
    RegExp(r'[^A-Za-z0-9]'),
    '',
  );
}
