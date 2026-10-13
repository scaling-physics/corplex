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

/// One cited paper inside a `[@…]` marker, with its optional pinpoint:
/// `@key, p. 42` is key `key`, locator `42`, label `page`.
class CiteItem {
  const CiteItem(this.key, {this.locator, this.label});

  final String key;

  /// The pinpoint as written without its label (`42`, `3–5`, `2`), or free
  /// text when it didn't parse as a labelled locator.
  final String? locator;

  /// A CSL locator type (`page`, `chapter`, `section`, `figure`,
  /// `paragraph`, `volume`, `line`, `note`), or null for free text.
  final String? label;

  bool get hasLocator => locator != null && locator!.isNotEmpty;

  /// Whether the locator names several things (`3–5`, `3, 7`), which turns
  /// "p." into "pp.".
  bool get plural => hasLocator && _rangeMark.hasMatch(locator!);

  /// The locator as printed in a hand-written style: `p. 42`, `pp. 3–5`,
  /// `chap. 2`; free text as is. Null without a locator.
  String? get display {
    if (!hasLocator) return null;
    final l = label;
    if (l == null) return locator;
    return '${locatorAbbreviation(l, plural: plural)} $locator';
  }

  /// This item as written inside a marker: `@key, p. 42`.
  String get markup => hasLocator
      ? '@$key, ${label == null ? '' : '${locatorAbbreviation(label!, plural: plural)} '}$locator'
      : '@$key';

  @override
  bool operator ==(Object other) =>
      other is CiteItem &&
      other.key == key &&
      other.locator == locator &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, locator, label);

  @override
  String toString() => 'CiteItem($markup)';
}

final _rangeMark = RegExp(r'[,&\-–—]');

/// The locator types a citation can carry, in the order a picker shows them.
const locatorLabels = [
  'page',
  'chapter',
  'section',
  'figure',
  'paragraph',
  'volume',
  'line',
  'note',
];

/// `p.` / `pp.`, `chap.`, `sec.`, `fig.`, `para.`, `vol.`, `l.` / `ll.`,
/// `n.` / `nn.` for a CSL locator type.
String locatorAbbreviation(String label, {bool plural = false}) =>
    switch (label) {
      'page' => plural ? 'pp.' : 'p.',
      'chapter' => plural ? 'chaps.' : 'chap.',
      'section' => plural ? 'secs.' : 'sec.',
      'figure' => plural ? 'figs.' : 'fig.',
      'paragraph' => plural ? 'paras.' : 'para.',
      'volume' => plural ? 'vols.' : 'vol.',
      'line' => plural ? 'll.' : 'l.',
      'note' => plural ? 'nn.' : 'n.',
      _ => label,
    };

/// "Page", "Chapter" … for a picker.
String locatorName(String label) =>
    label.isEmpty ? label : '${label[0].toUpperCase()}${label.substring(1)}';

final _itemPattern = RegExp(r'^@([A-Za-z0-9_:.\-]+)(?:\s*,\s*(.*))?$');

// Longest alternatives first; one-letter forms need their period.
final _labelPattern = RegExp(
  r'^(?:(pp?)\.?|(pages?)|(chaps?|chs?)\.?|(chapters?)|(secs?)\.?|(sections?)|'
  r'(§§?)|(figs?)\.?|(figures?)|(paras?)\.?|(paragraphs?)|(¶¶?)|'
  r'(vols?)\.?|(volumes?)|(ll?)\.|(nn?)\.|(notes?))(?=[\s\d]|$)\s*(.*)$',
  caseSensitive: false,
);
final _bareLocator = RegExp(
  r'^[A-Za-z]?\d+[A-Za-z]?(\s*[,&\-–—]\s*[A-Za-z]?\d+[A-Za-z]?)*$',
);

String _normalizeRange(String s) =>
    s.replaceAllMapped(RegExp(r'(\d)\s*-\s*(?=\d)'), (m) => '${m[1]}–');

String? _labelOf(RegExpMatch m) {
  const labels = [
    'page',
    'page',
    'chapter',
    'chapter',
    'section',
    'section',
    'section',
    'figure',
    'figure',
    'paragraph',
    'paragraph',
    'paragraph',
    'volume',
    'volume',
    'line',
    'note',
    'note',
  ];
  for (var i = 1; i <= labels.length; i++) {
    if (m.group(i) != null) return labels[i - 1];
  }
  return null;
}

/// The items of one marker such as `[@a, pp. 3–5; @b]`. Text after a comma
/// is a locator: a leading `p.`/`pp.`/`page`, `chap.`/`ch.`, `sec.`/`§`,
/// `fig.`, `para.`/`¶`, `vol.`, `l.`/`ll.`, `n.` sets its label, a bare
/// number means a page, anything else is kept as free text without a
/// label. Parts that aren't a citekey (the `[@?]` to-do marker) are
/// skipped. Ranges written with a hyphen print with an en dash.
List<CiteItem> parseCitationGroup(String marker) {
  var inner = marker.trim();
  if (inner.startsWith('[')) inner = inner.substring(1);
  if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);
  final out = <CiteItem>[];
  for (final part in inner.split(';')) {
    final m = _itemPattern.firstMatch(part.trim());
    if (m == null) continue;
    final key = m.group(1)!;
    final rest = (m.group(2) ?? '').trim();
    if (rest.isEmpty) {
      out.add(CiteItem(key));
      continue;
    }
    final lm = _labelPattern.firstMatch(rest);
    if (lm != null && lm.group(18)!.trim().isNotEmpty) {
      out.add(
        CiteItem(
          key,
          locator: _normalizeRange(lm.group(18)!.trim()),
          label: _labelOf(lm),
        ),
      );
    } else if (_bareLocator.hasMatch(rest)) {
      out.add(CiteItem(key, locator: _normalizeRange(rest), label: 'page'));
    } else {
      out.add(CiteItem(key, locator: rest));
    }
  }
  return out;
}

/// A marker for [items]: `[@a, p. 3; @b]`.
String citationMarkerFor(List<CiteItem> items) =>
    '[${items.map((i) => i.markup).join('; ')}]';

/// Citekeys used in [text], in order of first use. Locators are ignored.
List<String> citedKeys(String text) {
  final keys = <String>[];
  for (final m in _group.allMatches(text)) {
    for (final item in parseCitationGroup(m.group(0)!)) {
      if (!keys.contains(item.key)) keys.add(item.key);
    }
  }
  return keys;
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
///
/// A [locator] (with its CSL [label], default page) is added: `(Vaswani et
/// al., 2017, p. 42)`, MLA `(Vaswani 42)`.
String inTextCitation(
  Paper paper,
  CitationStyle style, {
  String? locator,
  String? label,
}) {
  final cite = locator == null || locator.isEmpty
      ? null
      : CiteItem('', locator: locator, label: label);
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

  final pin = cite?.display;
  return switch (style) {
    CitationStyle.mla =>
      pin == null
          ? '(${who()})'
          : cite!.label == 'page'
          ? '(${who()} ${cite.locator})'
          : '(${who()}, $pin)',
    _ => pin == null ? '(${who()}, $year)' : '(${who()}, $year, $pin)',
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
    final items = parseCitationGroup(m.group(0)!);
    if (items.isEmpty || items.any((i) => !byKey.containsKey(i.key))) {
      return m.group(0)!;
    }
    for (final i in items) {
      if (!_order.contains(i.key)) _order.add(i.key);
    }
    if (style == CitationStyle.ieee) {
      return items
          .map((i) {
            final n = _order.indexOf(i.key) + 1;
            return i.display == null ? '[$n]' : '[$n, ${i.display}]';
          })
          .join('');
    }
    String one(CiteItem i) => inTextCitation(
      byKey[i.key]!,
      style,
      locator: i.locator,
      label: i.label,
    );
    if (items.length == 1) return one(items.single);
    // (A, 2017; B, 2019)
    final parts = [
      for (final i in items) one(i).replaceAll(RegExp(r'^\(|\)$'), ''),
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
