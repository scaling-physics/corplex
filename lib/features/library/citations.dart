import 'package:drift/drift.dart';

import '../../data/database.dart';
import 'authors.dart';
import 'citation_formatter.dart';

/// Inline citations in notes are plain text, `[@vaswani2017]` (or
/// `[@a2017; @b2019]`), so they sync, copy and export like anything else.
/// A paper's citekey is assigned the first time it is cited and then never
/// changes, so old notes keep resolving after the metadata is edited.
String citationMarker(String citekey) => '[@$citekey]';

/// `vaswani2017`, or `smith` + first title word when there's no year, or
/// `paper` when there's nothing to go on. ASCII lowercase letters/digits.
String citekeyBase(Paper paper) {
  final authors = parseAuthors(paper.authors).authors;
  var who = authors.isEmpty ? '' : authors.first.family.split(' ').last;
  if (who.isEmpty) {
    who = paper.title
        .split(RegExp(r'\s+'))
        .firstWhere((w) => w.length > 3, orElse: () => 'paper');
  }
  who = _ascii(who);
  if (who.isEmpty) who = 'paper';
  return '$who${paper.year ?? ''}';
}

String _ascii(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// The paper's citekey, assigned (and saved) now if it has none. Collisions
/// get `a`, `b`, … suffixes.
Future<String> ensureCitekey(AppDatabase db, String paperId) async {
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(paperId))).getSingle();
  if (paper.citekey != null && paper.citekey!.isNotEmpty) return paper.citekey!;
  final taken = {
    for (final r
        in await db
            .customSelect(
              'SELECT citekey FROM papers WHERE citekey IS NOT NULL',
            )
            .get())
      r.read<String>('citekey'),
  };
  final base = citekeyBase(paper);
  var key = base;
  for (var i = 0; taken.contains(key); i++) {
    key = '$base${String.fromCharCode(97 + i % 26)}${i >= 26 ? i ~/ 26 : ''}';
  }
  await (db.update(db.papers)..where((p) => p.id.equals(paperId))).write(
    PapersCompanion(citekey: Value(key)),
  );
  return key;
}

final _group = RegExp(r'\[@[^\]]+\]');
final _keyPattern = RegExp(r'^[A-Za-z0-9_:.\-]+$');

/// Citekeys used in [text], in order of first use.
List<String> citedKeys(String text) {
  final keys = <String>[];
  for (final m in _group.allMatches(text)) {
    for (final key in _keysIn(m.group(0)!)) {
      if (!keys.contains(key)) keys.add(key);
    }
  }
  return keys;
}

Iterable<String> _keysIn(String group) sync* {
  final inner = group.substring(1, group.length - 1); // drop [ ]
  for (final part in inner.split(';')) {
    final key = part.trim().replaceFirst('@', '');
    if (key.isNotEmpty && _keyPattern.hasMatch(key)) yield key;
  }
}

/// The papers behind [keys], in the order of [keys]; unknown keys are
/// skipped.
Future<List<Paper>> papersForCitekeys(AppDatabase db, List<String> keys) async {
  if (keys.isEmpty) return const [];
  final rows = await (db.select(
    db.papers,
  )..where((p) => p.citekey.isIn(keys))).get();
  final byKey = {for (final p in rows) p.citekey!: p};
  return [for (final k in keys) ?byKey[k]];
}

/// `(Vaswani et al., 2017)` in APA/Harvard/Chicago, `(Vaswani)` in MLA,
/// `[1]` numbering is handled by [replaceCitations] for IEEE.
String inTextCitation(Paper paper, CitationStyle style) {
  final list = parseAuthors(paper.authors);
  final year = paper.year?.toString() ?? 'n.d.';
  String who() {
    final a = list.authors;
    if (a.isEmpty) return paper.title.split(RegExp(r'\s+')).take(3).join(' ');
    if (list.etAl || a.length >= 3) return '${a.first.family} et al.';
    if (a.length == 2) {
      final sep = style == CitationStyle.apa ? ' & ' : ' and ';
      return '${a[0].family}$sep${a[1].family}';
    }
    return a.single.family;
  }

  return switch (style) {
    CitationStyle.mla => '(${who()})',
    _ => '(${who()}, $year)',
  };
}

/// The reference list for [papers]: alphabetical (author-date styles) or in
/// citation order (IEEE, numbered `[1]`).
List<String> referenceList(List<Paper> papers, CitationStyle style) {
  if (style == CitationStyle.ieee) {
    return [
      for (final (i, p) in papers.indexed)
        '[${i + 1}] ${formatCitation(p, style)}',
    ];
  }
  final lines = [for (final p in papers) formatCitation(p, style)]
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return lines;
}

/// Resolves `[@key]` citations across several pieces of text, keeping one
/// citation order so numbered styles (IEEE) stay consistent. Citations
/// whose key is unknown are left as written.
class CitationResolver {
  CitationResolver(this.byKey, this.style);

  final Map<String, Paper> byKey;
  final CitationStyle style;
  final _order = <String>[];

  /// The papers cited so far, in citation order.
  List<Paper> get cited => [for (final k in _order) byKey[k]!];

  String replace(String text) => text.replaceAllMapped(_group, (m) {
    final keys = _keysIn(m.group(0)!).toList();
    if (keys.isEmpty || keys.any((k) => !byKey.containsKey(k))) {
      return m.group(0)!;
    }
    for (final k in keys) {
      if (!_order.contains(k)) _order.add(k);
    }
    if (style == CitationStyle.ieee) {
      return keys.map((k) => '[${_order.indexOf(k) + 1}]').join('');
    }
    if (keys.length == 1) return inTextCitation(byKey[keys.single]!, style);
    // (A, 2017; B, 2019)
    final parts = [
      for (final k in keys)
        inTextCitation(byKey[k]!, style).replaceAll(RegExp(r'^\(|\)$'), ''),
    ];
    return '(${parts.join('; ')})';
  });
}

/// Replaces every `[@key]` in [text] with its in-text form for [style]
/// (numbers for IEEE) and returns the papers cited, in citation order.
({String text, List<Paper> cited}) replaceCitations(
  String text,
  Map<String, Paper> byKey,
  CitationStyle style,
) {
  final resolver = CitationResolver(byKey, style);
  final out = resolver.replace(text);
  return (text: out, cited: resolver.cited);
}
