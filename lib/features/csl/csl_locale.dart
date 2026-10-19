import 'package:xml/xml.dart';

const _xmlNs = 'http://www.w3.org/XML/1998/namespace';

/// The `xml:lang` of [e], or null.
String? xmlLang(XmlElement e) => e.getAttribute('lang', namespaceUri: _xmlNs);

/// The language part of a tag: `de-AT` -> `de`.
String languageOf(String tag) => tag.split(RegExp(r'[-_]')).first.toLowerCase();

/// One `ordinal` / `ordinal-NN` term.
class _Ordinal {
  _Ordinal(this.number, this.match, this.genderForm, this.text);

  /// Null for the plain `ordinal` term.
  final int? number;
  final String match;
  final String? genderForm;
  final String text;

  String get key => '${number ?? 'x'}|${genderForm ?? ''}';
}

/// A CSL locale: terms ("editor", "et al."), ordinals, the date layouts and
/// a few style options. [tag] is the language it speaks (`de-AT`).
///
/// A locale used for formatting is composed from layers, most general first
/// (CSL 1.0.2, "Locale Fallback"): the en-US file, the language's primary
/// dialect (`de-DE`), the exact dialect file (`de-AT`), then the style's own
/// `<locale>` blocks without a language, with the language (`de`) and with
/// the exact tag. See [overlay] and [withOverrides].
class CslLocale {
  CslLocale._(
    this.tag,
    this._terms,
    this._genders,
    this._ordinals,
    this.dateForms,
  );

  /// The language this locale was composed for.
  final String tag;

  /// term name -> form (`long`, or `long|feminine` for a gendered variant)
  /// -> [single, multiple].
  final Map<String, Map<String, List<String>>> _terms;

  /// term name -> its grammatical gender (`gender` attribute).
  final Map<String, String> _genders;

  final Map<String, _Ordinal> _ordinals;

  /// `text` / `numeric` -> the `<date>` element.
  final Map<String, XmlElement> dateForms;

  bool _pq = true;
  bool _pqSet = false;
  bool _limitDay1 = false;

  /// Whether a full stop or comma goes inside closing quotes (en-US) or
  /// after them (German, French …).
  bool get punctuationInQuote => _pq;

  /// Whether this locale limits ordinal days to the 1st (French "1er").
  bool get limitDayOrdinalsToDay1 => _limitDay1;

  /// Reads a locale file (or a style's `<locale>` element). [tag] defaults
  /// to the file's `xml:lang`, else `en-US`.
  factory CslLocale.parse(String xml, {String? tag}) {
    final root = XmlDocument.parse(xml).rootElement;
    final l = CslLocale._(tag ?? xmlLang(root) ?? 'en-US', {}, {}, {}, {});
    l._apply(root);
    return l;
  }

  CslLocale _copy({String? tag}) =>
      CslLocale._(
          tag ?? this.tag,
          {for (final e in _terms.entries) e.key: Map.of(e.value)},
          Map.of(_genders),
          Map.of(_ordinals),
          Map.of(dateForms),
        )
        .._pq = _pq
        .._pqSet = _pqSet
        .._limitDay1 = _limitDay1;

  /// A copy with everything [over] defines replacing this locale's entries;
  /// the tag becomes [over]'s. An `over` that defines any ordinal replaces
  /// all of them (an English "st" must not survive in German).
  CslLocale overlay(CslLocale over) {
    final out = _copy(tag: over.tag);
    for (final e in over._terms.entries) {
      (out._terms[e.key] ??= {}).addAll(e.value);
    }
    out._genders.addAll(over._genders);
    if (over._ordinals.isNotEmpty) {
      out._ordinals
        ..clear()
        ..addAll(over._ordinals);
    }
    out.dateForms.addAll(over.dateForms);
    if (over._pqSet) {
      out
        .._pq = over._pq
        .._pqSet = true;
    }
    if (over._limitDay1) out._limitDay1 = true;
    return out;
  }

  /// Composes [files] (most general first) into one locale.
  static CslLocale compose(List<CslLocale> files) {
    var out = files.first;
    for (final f in files.skip(1)) {
      out = out.overlay(f);
    }
    return out;
  }

  /// Reads `<terms>`, `<date>` and `<style-options>` children of [root] over
  /// this locale (in place; only used on copies).
  void _apply(XmlElement root) {
    for (final e in root.childElements) {
      switch (e.name.local) {
        case 'style-options':
          final v = e.getAttribute('punctuation-in-quote');
          if (v != null) {
            _pq = v == 'true';
            _pqSet = true;
          }
          final d = e.getAttribute('limit-day-ordinals-to-day-1');
          if (d != null) _limitDay1 = d == 'true';
        case 'date':
          final f = e.getAttribute('form');
          if (f != null) dateForms[f] = e;
        case 'terms':
          final all = e.childElements.where((c) => c.name.local == 'term');
          final hasOrdinal = all.any(
            (t) => (t.getAttribute('name') ?? '').startsWith('ordinal'),
          );
          if (hasOrdinal) _ordinals.clear();
          for (final t in all) {
            _readTerm(t);
          }
      }
    }
  }

  void _readTerm(XmlElement t) {
    final name = t.getAttribute('name');
    if (name == null) return;
    final form = t.getAttribute('form') ?? 'long';
    final genderForm = t.getAttribute('gender-form');
    final gender = t.getAttribute('gender');
    if (gender != null) _genders[name] = gender;
    final single = t.childElements.where((c) => c.name.local == 'single');
    final multiple = t.childElements.where((c) => c.name.local == 'multiple');
    final List<String> values;
    if (single.isNotEmpty || multiple.isNotEmpty) {
      final s = single.isEmpty ? '' : single.first.innerText;
      values = [s, multiple.isEmpty ? s : multiple.first.innerText];
    } else {
      final s = t.innerText;
      values = [s, s];
    }
    final ord = RegExp(r'^ordinal(?:-(\d\d))?$').firstMatch(name);
    if (ord != null) {
      final n = ord[1] == null ? null : int.parse(ord[1]!);
      final o = _Ordinal(
        n,
        t.getAttribute('match') ??
            (n == null || n < 10 ? 'last-digit' : 'last-two-digits'),
        genderForm,
        values[0],
      );
      _ordinals[o.key] = o;
      return;
    }
    final key = genderForm == null ? form : '$form|$genderForm';
    (_terms[name] ??= {})[key] = values;
  }

  /// A copy without the terms [names]. Corplex has no volume or pages, so
  /// "ahead of print" would be wrong on every article.
  CslLocale withoutTerms(Set<String> names) {
    final out = _copy();
    out._terms.removeWhere((k, _) => names.contains(k));
    return out;
  }

  /// A copy with the `<locale>` blocks of a style merged in, in the order
  /// CSL prescribes: blocks without `xml:lang`, then those for just the
  /// language (`de`), then those for exactly [tag]. Blocks for other
  /// languages (or other dialects) don't apply.
  CslLocale withOverrides(Iterable<XmlElement> locales) {
    final lang = languageOf(tag);
    final all = locales.toList();
    var out = this;
    bool matches(XmlElement e, int level) {
      final l = xmlLang(e);
      return switch (level) {
        0 => l == null,
        1 =>
          l != null &&
              l.toLowerCase() == lang &&
              l.toLowerCase() != tag.toLowerCase(),
        _ => l != null && l.toLowerCase() == tag.toLowerCase(),
      };
    }

    for (var level = 0; level < 3; level++) {
      for (final b in all.where((e) => matches(e, level))) {
        out = out._withBlock(b);
      }
    }
    return out;
  }

  CslLocale _withBlock(XmlElement block) => _copy().._apply(block);

  /// The term, or null. Falls back the way CSL does: verb-short to verb to
  /// long, symbol to short to long, short to long. [gender] picks a
  /// gendered variant (`feminine`) where the locale has one.
  String? term(
    String name, {
    String form = 'long',
    bool plural = false,
    String? gender,
  }) {
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
      final v = (gender == null ? null : forms['$f|$gender']) ?? forms[f];
      if (v != null) return plural ? v[1] : v[0];
    }
    return null;
  }

  bool hasTerm(String name) => _terms.containsKey(name);

  /// The grammatical gender the locale gives term [name] (`masculine`,
  /// `feminine`), or null.
  String? genderOf(String name) => _genders[name];

  String get openQuote => term('open-quote') ?? '“';
  String get closeQuote => term('close-quote') ?? '”';
  String get openInnerQuote => term('open-inner-quote') ?? '‘';
  String get closeInnerQuote => term('close-inner-quote') ?? '’';

  /// 1 -> st, 2 -> nd, 11 -> th … Matching follows CSL: an `ordinal-NN`
  /// term with `match="whole-number"`, then one matching the last two
  /// digits, then one matching the last digit, then plain `ordinal`. A
  /// gendered variant is preferred when [gender] is given.
  String ordinalSuffix(int n, {String? gender}) {
    final two = n % 100, one = n % 10;
    bool fits(_Ordinal o) {
      final x = o.number;
      if (x == null) return false;
      return switch (o.match) {
        'whole-number' => x == n,
        'last-two-digits' => x == two,
        _ => x < 10 ? x == one : x == two,
      };
    }

    String? pick(bool Function(_Ordinal) test) {
      _Ordinal? plain;
      for (final o in _ordinals.values) {
        if (!test(o)) continue;
        if (gender != null && o.genderForm == gender) return o.text;
        if (o.genderForm == null) plain = o;
      }
      return plain?.text;
    }

    return pick((o) => o.match == 'whole-number' && fits(o)) ??
        pick((o) => o.match == 'last-two-digits' && fits(o)) ??
        pick((o) => o.match == 'last-digit' && fits(o)) ??
        pick((o) => o.number == null) ??
        '';
  }
}
