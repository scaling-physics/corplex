import 'package:xml/xml.dart';

/// A CSL locale: terms ("editor", "et al."), the date layouts and a few
/// style options. Only the bundled en-US file is shipped; a style's own
/// `<locale>` blocks are merged over it.
class CslLocale {
  CslLocale._(this._terms, this.dateForms, this.punctuationInQuote);

  /// term name -> form -> [single, multiple].
  final Map<String, Map<String, List<String>>> _terms;

  /// `text` / `numeric` -> the `<date>` element.
  final Map<String, XmlElement> dateForms;

  final bool punctuationInQuote;

  factory CslLocale.parse(String xml) {
    final root = XmlDocument.parse(xml).rootElement;
    final terms = <String, Map<String, List<String>>>{};
    final dates = <String, XmlElement>{};
    var pq = true;
    _readInto(root, terms, dates, (v) => pq = v);
    return CslLocale._(terms, dates, pq);
  }

  static void _readInto(
    XmlElement root,
    Map<String, Map<String, List<String>>> terms,
    Map<String, XmlElement> dates,
    void Function(bool) setPq,
  ) {
    for (final e in root.childElements) {
      switch (e.name.local) {
        case 'style-options':
          final v = e.getAttribute('punctuation-in-quote');
          if (v != null) setPq(v == 'true');
        case 'date':
          final f = e.getAttribute('form');
          if (f != null) dates[f] = e;
        case 'terms':
          for (final t in e.childElements.where(
            (c) => c.name.local == 'term',
          )) {
            final name = t.getAttribute('name');
            if (name == null) continue;
            final form = t.getAttribute('form') ?? 'long';
            final single = t.childElements.where(
              (c) => c.name.local == 'single',
            );
            final multiple = t.childElements.where(
              (c) => c.name.local == 'multiple',
            );
            final List<String> values;
            if (single.isNotEmpty || multiple.isNotEmpty) {
              final s = single.isEmpty ? '' : single.first.innerText;
              values = [s, multiple.isEmpty ? s : multiple.first.innerText];
            } else {
              final s = t.innerText;
              values = [s, s];
            }
            (terms[name] ??= {})[form] = values;
          }
      }
    }
  }

  /// A copy without the terms [names]. Corplex has no volume or pages, so
  /// "ahead of print" would be wrong on every article.
  CslLocale withoutTerms(Set<String> names) => CslLocale._(
    {
      for (final e in _terms.entries)
        if (!names.contains(e.key)) e.key: e.value,
    },
    dateForms,
    punctuationInQuote,
  );

  /// A copy with the `<locale>` blocks of a style merged in.
  CslLocale withOverrides(Iterable<XmlElement> locales) {
    final terms = {for (final e in _terms.entries) e.key: Map.of(e.value)};
    final dates = Map.of(dateForms);
    var pq = punctuationInQuote;
    for (final l in locales) {
      _readInto(l, terms, dates, (v) => pq = v);
    }
    return CslLocale._(terms, dates, pq);
  }

  /// The term, or null. Falls back the way CSL does: verb-short to verb to
  /// long, symbol to short to long, short to long.
  String? term(String name, {String form = 'long', bool plural = false}) {
    final forms = _terms[name];
    if (forms == null) return null;
    final order = switch (form) {
      'verb-short' => ['verb-short', 'verb', 'long'],
      'verb' => ['verb', 'long'],
      'symbol' => ['symbol', 'short', 'long'],
      'short' => ['short', 'long'],
      _ => ['long'],
    };
    for (final f in order) {
      final v = forms[f];
      if (v != null) return plural ? v[1] : v[0];
    }
    return null;
  }

  bool hasTerm(String name) => _terms.containsKey(name);

  String get openQuote => term('open-quote') ?? '“';
  String get closeQuote => term('close-quote') ?? '”';
  String get openInnerQuote => term('open-inner-quote') ?? '‘';
  String get closeInnerQuote => term('close-inner-quote') ?? '’';

  /// 1 -> st, 2 -> nd, 11 -> th …
  String ordinalSuffix(int n) {
    final two = n % 100;
    final exact = term('ordinal-${n.toString().padLeft(2, '0')}');
    if (exact != null && n < 100) return exact;
    if (two >= 11 && two <= 13) {
      return term('ordinal-$two') ?? term('ordinal') ?? 'th';
    }
    final last = n % 10;
    if (last >= 1 && last <= 3) {
      return term('ordinal-0$last') ?? term('ordinal') ?? 'th';
    }
    return term('ordinal') ?? 'th';
  }
}
