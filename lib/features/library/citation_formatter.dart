import '../../data/database.dart';
import '../csl/csl_item.dart';
import '../csl/csl_processor.dart';
import '../csl/csl_registry.dart';
import '../csl/csl_style.dart';
import 'authors.dart';

/// A way of formatting references. The first five are real CSL styles
/// (bundled, `assets/csl/`) with the hand-written formatter below as a
/// fallback until the CSL file has loaded (it loads asynchronously; see
/// [ensureLoaded]). Styles the reader imports are added at runtime. BibTeX is
/// always hand-written. Compare by identity.
class CitationStyle {
  const CitationStyle._(
    this.name,
    this.label, {
    this.cslFile,
    this.hand,
    this.numeric = false,
    this.custom = false,
  });

  /// Stable id.
  final String name;
  final String label;

  /// File in `assets/csl/`, for bundled CSL styles.
  final String? cslFile;

  /// Which hand-written formatter backs it ("apa" when null).
  final String? hand;
  final bool numeric;

  /// Imported by the reader.
  final bool custom;

  static const apa = CitationStyle._(
    'apa',
    'APA',
    cslFile: 'apa.csl',
    hand: 'apa',
  );
  static const mla = CitationStyle._(
    'mla',
    'MLA',
    cslFile: 'modern-language-association.csl',
    hand: 'mla',
  );
  static const chicago = CitationStyle._(
    'chicago',
    'Chicago',
    cslFile: 'chicago-author-date.csl',
    hand: 'chicago',
  );
  static const harvard = CitationStyle._(
    'harvard',
    'Harvard',
    cslFile: 'harvard-cite-them-right.csl',
    hand: 'harvard',
  );
  static const ieee = CitationStyle._(
    'ieee',
    'IEEE',
    cslFile: 'ieee.csl',
    hand: 'ieee',
    numeric: true,
  );
  static const vancouver = CitationStyle._(
    'vancouver',
    'Vancouver',
    cslFile: 'nlm-citation-sequence.csl',
    numeric: true,
  );
  static const nature = CitationStyle._(
    'nature',
    'Nature',
    cslFile: 'nature.csl',
    numeric: true,
  );
  static const science = CitationStyle._(
    'science',
    'Science',
    cslFile: 'science.csl',
    numeric: true,
  );
  static const acm = CitationStyle._(
    'acm',
    'ACM',
    cslFile: 'association-for-computing-machinery.csl',
    numeric: true,
  );
  static const elsevierHarvard = CitationStyle._(
    'elsevier-harvard',
    'Elsevier Harvard',
    cslFile: 'elsevier-harvard.csl',
  );
  static const bibtex = CitationStyle._('bibtex', 'BibTeX', hand: 'bibtex');

  static const _bundled = [
    apa,
    mla,
    chicago,
    harvard,
    ieee,
    vancouver,
    nature,
    science,
    acm,
    elsevierHarvard,
  ];

  static const _legacy = [apa, mla, chicago, harvard, ieee, bibtex];

  static final _customStyles = <String, CitationStyle>{};

  /// Every style a picker should offer: the bundled CSL styles, then the
  /// reader's own, then BibTeX last. Imported styles appear once
  /// [CslRegistry.loadCustom] has run.
  static List<CitationStyle> get all => [..._bundled, ...customStyles, bibtex];

  /// The reader's imported styles.
  static List<CitationStyle> get customStyles => [
    for (final c in CslRegistry.custom)
      _customStyles[c.name] ??= CitationStyle._(
        c.name,
        c.label,
        custom: true,
        numeric: CslRegistry.cached(c.name)?.numeric ?? false,
      ),
  ];

  /// The long-standing five plus BibTeX, and any other style that has
  /// already loaded (so a list never offers a style it would format with the
  /// wrong fallback). Use [all] for pickers that load styles first.
  static List<CitationStyle> get values => [
    for (final s in _legacy)
      if (s != bibtex) s,
    for (final s in _bundled)
      if (!_legacy.contains(s) && CslRegistry.cached(s.name) != null) s,
    ...customStyles,
    bibtex,
  ];

  /// The style called [name], or null.
  static CitationStyle? byName(String name) {
    for (final s in all) {
      if (s.name == name) return s;
    }
    return null;
  }

  bool get isCsl => cslFile != null || custom;

  /// The loaded CSL style, or null if this isn't one or it hasn't loaded.
  CslStyle? get csl => isCsl ? CslRegistry.cached(name) : null;

  /// Loads the CSL file (a no-op for BibTeX and when already loaded).
  Future<CslStyle?> ensureLoaded() async {
    if (!isCsl) return null;
    return custom
        ? CslRegistry.ensureCustom(name)
        : CslRegistry.ensureBundled(name, cslFile!);
  }

  @override
  String toString() => 'CitationStyle($name)';
}

/// A single reference in [style]. CSL styles use their real rules once
/// loaded (numbered styles leave the number out; see
/// `bibliographyEntries` in `csl_format.dart` for numbering); until then the
/// hand-written formatter answers.
String formatCitation(Paper paper, CitationStyle style) {
  final loaded = style.csl;
  if (loaded != null) {
    try {
      final out = CslProcessor(loaded)
          .process([paperToCsl(paper)], suppressNumbers: true);
      final text = out.bibliography.first.plain.trim();
      if (text.isNotEmpty) return text;
    } catch (_) {
      // Fall through to the hand-written formatter.
    }
  }
  return _formatHand(paper, style.hand ?? 'apa');
}

String _formatHand(Paper paper, String hand) {
  final list = parseAuthors(paper.authors);
  final title = paper.title.trim();
  final venue = paper.venue?.trim() ?? '';
  final year = paper.year?.toString() ?? 'n.d.';

  switch (hand) {
    case 'apa':
      final buffer = StringBuffer();
      final apa = authorsApa(list);
      if (apa.isNotEmpty) buffer.write('$apa ');
      buffer.write('($year). $title.');
      if (venue.isNotEmpty) buffer.write(' $venue.');
      return buffer.toString().trim();

    case 'mla':
      final buffer = StringBuffer();
      final mla = authorsMla(list);
      if (mla.isNotEmpty) buffer.write('$mla ');
      buffer.write('"$title."');
      if (venue.isNotEmpty) buffer.write(' $venue,');
      buffer.write(' $year.');
      return buffer.toString().trim();

    case 'chicago':
      // Chicago author-date: Family, Given, and Given Family. Year. "Title." Venue.
      final buffer = StringBuffer();
      final names = _chicagoAuthors(list);
      if (names.isNotEmpty) buffer.write('$names. ');
      buffer.write('$year. "$title."');
      if (venue.isNotEmpty) buffer.write(' $venue.');
      return buffer.toString().trim();

    case 'harvard':
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

    case 'ieee':
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

    case 'bibtex':
      final lines = <String>['@article{${bibtexKey(paper)},'];
      lines.add('  title={$title},');
      if (!list.isEmpty) lines.add('  author={${authorsBibtex(list)}},');
      if (venue.isNotEmpty) lines.add('  journal={$venue},');
      if (paper.year != null) lines.add('  year={$year},');
      if ((paper.doi ?? '').isNotEmpty) lines.add('  doi={${paper.doi}},');
      lines.add('}');
      return lines.join('\n');
  }
  return title;
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
