/// One author, split into the parts citation styles need.
class Author {
  const Author({required this.family, this.given = ''});

  final String family;
  final String given;

  /// "A." / "J.-P." style initials from [given]; empty if there's no
  /// given name.
  String get initials => given
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map(
        (t) => t
            .split('-')
            .where((p) => p.isNotEmpty)
            .map((p) => p.endsWith('.') && p.length <= 2 ? p : '${p[0]}.')
            .join('-'),
      )
      .join(' ');

  /// "Family, Given" (or just the family name).
  String get inverted => given.isEmpty ? family : '$family, $given';

  /// "Given Family".
  String get natural => given.isEmpty ? family : '$given $family';

  @override
  bool operator ==(Object other) =>
      other is Author && other.family == family && other.given == given;

  @override
  int get hashCode => Object.hash(family, given);

  @override
  String toString() => inverted;
}

/// The authors of a paper, parsed from whatever the reader typed or a
/// source supplied.
class AuthorList {
  const AuthorList(this.authors, {this.etAl = false});

  final List<Author> authors;

  /// The source said "…, et al." — there are more authors than listed.
  final bool etAl;

  bool get isEmpty => authors.isEmpty;

  bool get hasGivenNames => authors.any((a) => a.given.isNotEmpty);
}

const _particles = {
  'van',
  'von',
  'de',
  'der',
  'den',
  'del',
  'della',
  'di',
  'da',
  'dos',
  'du',
  'la',
  'le',
  'ten',
  'ter',
  'bin',
  'ibn',
  'al',
  'el',
};

/// Understands the shapes people actually write:
///
/// * `Ashish Vaswani; Noam Shazeer` / `… and …` / one per line
/// * `Vaswani, Ashish and Shazeer, Noam` (BibTeX)
/// * `Ashish Vaswani, Noam Shazeer` (comma-separated)
/// * `Vaswani et al.`
AuthorList parseAuthors(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const AuthorList([]);

  var etAl = false;
  final etAlMatch = RegExp(
    r'[,;]?\s*(et\.? ?al\.?|and others)\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (etAlMatch != null) {
    etAl = true;
    text = text.substring(0, etAlMatch.start).trim();
  }

  var parts = text
      .split(RegExp(r'\s*(?:;|\n|&|\band\b)\s*', caseSensitive: false))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // A lone comma-separated string: either "Family, Given" or a list.
  if (parts.length == 1 && parts.single.contains(',')) {
    final pieces = parts.single
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (pieces.length == 2) {
      // "Vaswani, Ashish" — unless both halves are full names.
      final bothFull = pieces.every((p) => p.contains(' '));
      parts = bothFull ? pieces : [parts.single];
    } else if (pieces.every((p) => p.contains(' '))) {
      parts = pieces; // "Ashish Vaswani, Noam Shazeer, …"
    } else if (pieces.length.isEven) {
      // "Vaswani, Ashish, Shazeer, Noam" — Family, Given pairs.
      parts = [
        for (var i = 0; i < pieces.length; i += 2)
          '${pieces[i]}, ${pieces[i + 1]}',
      ];
    } else {
      parts = pieces;
    }
  }

  return AuthorList([for (final p in parts) _parseOne(p)], etAl: etAl);
}

Author _parseOne(String name) {
  if (name.contains(',')) {
    final i = name.indexOf(',');
    return Author(
      family: name.substring(0, i).trim(),
      given: name.substring(i + 1).trim(),
    );
  }
  final tokens = name.split(RegExp(r'\s+'));
  if (tokens.length == 1) return Author(family: tokens.single);
  // The family name is the last word, plus any particles before it
  // ("van der Berg", "de la Cruz").
  var start = tokens.length - 1;
  while (start > 1 && _particles.contains(tokens[start - 1].toLowerCase())) {
    start--;
  }
  return Author(
    family: tokens.sublist(start).join(' '),
    given: tokens.sublist(0, start).join(' '),
  );
}

/// APA 7: `Vaswani, A., Shazeer, N., & Parmar, N.`
String authorsApa(AuthorList list) {
  final names = [
    for (final a in list.authors)
      a.given.isEmpty ? a.family : '${a.family}, ${a.initials}',
  ];
  if (names.isEmpty) return '';
  if (list.etAl) return '${names.join(', ')} et al.';
  if (names.length == 1) return names.single;
  if (names.length <= 20) {
    return '${names.take(names.length - 1).join(', ')}, & ${names.last}';
  }
  return '${names.take(19).join(', ')}, . . . ${names.last}';
}

/// MLA 9: `Vaswani, Ashish, et al.` / `Vaswani, Ashish, and Noam Shazeer.`
String authorsMla(AuthorList list) {
  final a = list.authors;
  if (a.isEmpty) return '';
  String finish(String s) => s.endsWith('.') ? s : '$s.';
  if (list.etAl && !list.hasGivenNames) {
    return finish('${a.first.family} et al.');
  }
  if (a.length >= 3 || list.etAl) return finish('${a.first.inverted}, et al.');
  if (a.length == 2) {
    return finish('${a[0].inverted}, and ${a[1].natural}');
  }
  return finish(a.single.inverted);
}

/// BibTeX: `Vaswani, Ashish and Shazeer, Noam`.
String authorsBibtex(AuthorList list) {
  if (list.etAl && !list.hasGivenNames) {
    // Nothing structured to preserve; keep what the reader wrote.
    return '${list.authors.map((a) => a.family).join(' and ')} et al.';
  }
  final names = list.authors.map((a) => a.inverted).toList();
  if (list.etAl) names.add('others');
  return names.join(' and ');
}

/// Canonical form for storing: `Family, Given; Family, Given`. Round-trips
/// through [parseAuthors] and reads naturally in the UI.
String authorsToStored(AuthorList list) {
  final names = list.authors.map((a) => a.inverted).toList();
  return names.join('; ') + (list.etAl ? ' et al.' : '');
}

/// A short, readable line for [list]: "Ashish Vaswani, Noam Shazeer and
/// Niki Parmar", or past [max] names "Ashish Vaswani, Noam Shazeer,
/// Niki Parmar + 5 more".
String authorsSummary(AuthorList list, {int max = 3}) {
  final names = [for (final a in list.authors) a.natural];
  if (names.isEmpty) return '';
  if (names.length > max) {
    final more = names.length - max;
    return '${names.take(max).join(', ')} + $more more';
  }
  final shown = names.length == 1
      ? names.single
      : '${names.take(names.length - 1).join(', ')} and ${names.last}';
  return list.etAl ? '$shown et al.' : shown;
}

/// [authorsSummary] for a stored authors string, or the string itself if
/// it can't be read as names.
String displayAuthors(String raw, {int max = 3}) {
  final summary = authorsSummary(parseAuthors(raw), max: max);
  return summary.isEmpty ? raw : summary;
}
