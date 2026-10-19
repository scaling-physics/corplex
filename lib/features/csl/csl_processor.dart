import 'package:xml/xml.dart';

import 'csl_engine.dart';
import 'csl_rich.dart';
import 'csl_style.dart';

/// What [CslProcessor.process] produces.
class CslOutput {
  const CslOutput({
    required this.citations,
    required this.bibliography,
    required this.bibliographyOrder,
  });

  /// One per requested cluster, in the order asked.
  final List<CslRich> citations;

  /// Reference entries, already in the style's order.
  final List<CslRich> bibliography;

  /// For each bibliography entry, the index of its item in the input.
  final List<int> bibliographyOrder;
}

/// One cited item in a cluster, with its optional pinpoint (`p. 42`).
class CslCite {
  const CslCite(this.item, {this.locator, this.label = 'page'});

  /// Index into the items given to [CslProcessor.process].
  final int item;

  /// The pinpoint text, e.g. `42` or `3–5`; null for none.
  final String? locator;

  /// The CSL locator type: `page`, `chapter`, `section`, …
  final String label;
}

/// One rendered cite of a cluster, with its date markers, for collapsing.
class _Rendered {
  _Rendered(this.cite, this.spans, this.suffix);

  final CslCite cite;
  final List<CslSpan> spans;
  final String? suffix;

  late final String plain = spans.map((s) => s.text).join();
  late final int _ds = plain.indexOf(cslDateStart);
  late final int _de = plain.lastIndexOf(cslDateEnd);

  /// The text before the date (the authors), or null when this cite can't
  /// be collapsed into another: no date, or a pinpoint of its own.
  String? get collapseKey => _ds < 0 || _de < _ds || cite.locator != null
      ? null
      : plain.substring(0, _ds);

  /// The date without its year suffix: "2019" for "2019a".
  String get yearBase {
    final d = _strip(plain.substring(_ds, _de + 1));
    final s = suffix;
    return s != null && d.endsWith(s) ? d.substring(0, d.length - s.length) : d;
  }

  List<CslSpan> full() => _stripSpans(spans);

  List<CslSpan> dateOnly() => _stripSpans(_slice(spans, _ds));

  static final _markers = RegExp('[$cslDateStart$cslDateEnd]');

  static String _strip(String s) => s.replaceAll(_markers, '');

  static List<CslSpan> _stripSpans(List<CslSpan> spans) => [
    for (final s in spans)
      if (_strip(s.text).isNotEmpty) s.withText(_strip(s.text)),
  ];

  /// The spans from character offset [from] on.
  static List<CslSpan> _slice(List<CslSpan> spans, int from) {
    final out = <CslSpan>[];
    var at = 0;
    for (final s in spans) {
      final end = at + s.text.length;
      if (end > from) {
        out.add(from > at ? s.withText(s.text.substring(from - at)) : s);
      }
      at = end;
    }
    return out;
  }
}

class _State {
  int? useFirst;
  bool full = false;
  String? suffix;
}

/// Formats citations and a bibliography for a set of items in one CSL
/// style: sorting, citation numbers and disambiguation (extra names, given
/// names, year suffixes 2017a/2017b) happen here, across the whole set.
class CslProcessor {
  CslProcessor(this.style) : engine = CslEngine(style);

  final CslStyle style;
  final CslEngine engine;

  /// [items] are CSL-JSON maps in order of first citation (that order gives
  /// citation numbers). [clusters] are the in-text citations to format, as
  /// lists of indexes into [items]. [numbers] leaves numbering out of the
  /// entries (a single reference shown on its own). [cites] is the same as
  /// [clusters] but each cited item can carry a locator; it is used after
  /// [clusters].
  CslOutput process(
    List<Map<String, dynamic>> items, {
    List<List<int>> clusters = const [],
    List<List<CslCite>> cites = const [],
    bool suppressNumbers = false,
  }) {
    final data = [
      for (final (i, it) in items.indexed) {...it, 'citation-number': i + 1},
    ];
    final order = _bibliographyOrder(data);
    final states = [for (final _ in data) _State()];
    _disambiguate(data, states, order);

    CslContext ctxFor(
      int i, {
      bool bib = false,
      String position = 'first',
      CslCite? cite,
      bool markDates = false,
      AuthorSubstitute? substitute,
    }) => CslContext(
      data[i],
      bibliography: bib,
      suppressNumber: suppressNumbers,
      yearSuffix: states[i].suffix,
      etAlUseFirst: bib ? null : states[i].useFirst,
      fullNames: !bib && states[i].full,
      position: position,
      locator: cite?.locator,
      locatorLabel: cite?.label ?? 'page',
      markDates: markDates,
      substitute: substitute,
    );

    final substituteText = style.bibliography?.getAttribute(
      'subsequent-author-substitute',
    );
    final substituteRule =
        style.bibliography?.getAttribute('subsequent-author-substitute-rule') ??
        'complete-all';
    final bibliography = <CslRich>[];
    List<String>? previousNames;
    for (final i in order) {
      final sub = substituteText == null
          ? null
          : AuthorSubstitute(substituteText, substituteRule, previousNames);
      bibliography.add(
        engine.bibliographyEntry(ctxFor(i, bib: true, substitute: sub)),
      );
      previousNames = sub?.record;
    }

    final seen = <int>{};
    final citations = <CslRich>[];
    final layout = style.citationLayout;
    final delimiter = layout?.getAttribute('delimiter') ?? '';
    final collapse = style.citation?.getAttribute('collapse');
    final byYear =
        collapse == 'year' ||
        collapse == 'year-suffix' ||
        collapse == 'year-suffix-ranged';
    final all = [
      for (final c in clusters) [for (final i in c) CslCite(i)],
      ...cites,
    ];
    for (final cluster in all) {
      final sorted = _sortCluster(data, [for (final c in cluster) c.item]);
      final pending = [...cluster];
      final ordered = <CslCite>[
        for (final i in sorted)
          pending.removeAt(pending.indexWhere((c) => c.item == i)),
      ];
      final rendered = <CslRich>[];
      for (final c in ordered) {
        rendered.add(
          engine.citationItem(
            ctxFor(
              c.item,
              position: seen.contains(c.item) ? 'subsequent' : 'first',
              cite: c,
              markDates: byYear,
            ),
          ),
        );
      }
      seen.addAll(sorted);
      final spans = byYear
          ? _collapseByYear(ordered, rendered, states, collapse!, delimiter)
          : _joinCites(ordered, rendered, data, collapse, delimiter);
      citations.add(
        engine.wrapCitation(
          spans,
          ctxFor(cluster.isEmpty ? 0 : cluster.first.item),
        ),
      );
    }
    return CslOutput(
      citations: citations,
      bibliography: bibliography,
      bibliographyOrder: order,
    );
  }

  // ----------------------------------------------------------- joining

  /// The cites of a cluster joined by the layout's delimiter; with
  /// `collapse="citation-number"` runs of three or more consecutive numbers
  /// become a range ("1–3").
  List<CslSpan> _joinCites(
    List<CslCite> ordered,
    List<CslRich> rendered,
    List<Map<String, dynamic>> data,
    String? collapse,
    String delimiter,
  ) {
    final spans = <CslSpan>[];
    void add(List<CslSpan> s) {
      if (spans.isNotEmpty && delimiter.isNotEmpty) {
        spans.add(CslSpan(delimiter));
      }
      spans.addAll(s);
    }

    int number(int k) => data[ordered[k].item]['citation-number'] as int;
    final hasLocator = ordered.any((c) => c.locator != null);
    var k = 0;
    while (k < ordered.length) {
      if (collapse == 'citation-number' && !hasLocator) {
        var end = k;
        while (end + 1 < ordered.length && number(end + 1) == number(end) + 1) {
          end++;
        }
        if (end - k >= 2) {
          add(rendered[k].spans);
          spans.add(const CslSpan('–'));
          spans.addAll(rendered[end].spans);
          k = end + 1;
          continue;
        }
      }
      add(rendered[k].spans);
      k++;
    }
    return spans;
  }

  /// `collapse="year"` and friends. Cites by the same authors (the text
  /// before the date) are moved together ("cite grouping"); after the first,
  /// a group prints only the date, or with the year-suffix modes only the
  /// suffix when the year repeats ("Smith, 2019a, b"; ranged: "2019a–c").
  /// [rendered] carries date markers (see [cslDateStart]).
  List<CslSpan> _collapseByYear(
    List<CslCite> ordered,
    List<CslRich> rendered,
    List<_State> states,
    String collapse,
    String delimiter,
  ) {
    final part = style.citation;
    final groupDelimiter = part?.getAttribute('cite-group-delimiter') ?? ', ';
    final afterCollapse =
        part?.getAttribute('after-collapse-delimiter') ?? delimiter;
    final suffixDelimiter =
        part?.getAttribute('year-suffix-delimiter') ?? groupDelimiter;
    final suffixMode = collapse != 'year';
    final ranged = collapse == 'year-suffix-ranged';

    final groups = <List<_Rendered>>[];
    for (final (k, c) in ordered.indexed) {
      final it = _Rendered(c, rendered[k].spans, states[c.item].suffix);
      final key = it.collapseKey;
      if (key != null) {
        final home = groups.where((g) => g.first.collapseKey == key);
        if (home.isNotEmpty) {
          home.first.add(it);
          continue;
        }
      }
      groups.add([it]);
    }

    final out = <CslSpan>[];
    for (final (gi, g) in groups.indexed) {
      if (gi > 0) {
        final d = groups[gi - 1].length > 1 ? afterCollapse : delimiter;
        if (d.isNotEmpty) out.add(CslSpan(d));
      }
      out.addAll(g.first.full());
      var i = 1;
      while (i < g.length) {
        final prev = g[i - 1], cur = g[i];
        if (suffixMode &&
            cur.suffix != null &&
            prev.suffix != null &&
            cur.yearBase == prev.yearBase) {
          var r = i - 1;
          if (ranged) {
            while (r + 1 < g.length &&
                g[r + 1].yearBase == cur.yearBase &&
                g[r + 1].suffix != null &&
                _letterIndex(g[r + 1].suffix!) ==
                    _letterIndex(g[r].suffix!) + 1) {
              r++;
            }
          }
          if (ranged && r - (i - 1) >= 2) {
            out.add(const CslSpan('–'));
            out.add(CslSpan(g[r].suffix!));
            i = r + 1;
          } else {
            out.add(CslSpan(suffixDelimiter));
            out.add(CslSpan(cur.suffix!));
            i++;
          }
        } else {
          out.add(CslSpan(groupDelimiter));
          out.addAll(cur.dateOnly());
          i++;
        }
      }
    }
    return out;
  }

  static int _letterIndex(String s) {
    var n = 0;
    for (final r in s.runes) {
      n = n * 26 + (r - 96);
    }
    return n - 1;
  }

  // ------------------------------------------------------------ sorting

  List<XmlElement> _keys(XmlElement? parent) {
    final sort = parent?.childElements
        .where((e) => e.name.local == 'sort')
        .firstOrNull;
    return sort?.childElements.where((e) => e.name.local == 'key').toList() ??
        const [];
  }

  List<int> _bibliographyOrder(List<Map<String, dynamic>> data) {
    final keys = _keys(style.bibliography);
    final idx = List.generate(data.length, (i) => i);
    if (keys.isEmpty) return idx;
    return _sorted(data, idx, keys, bibliography: true);
  }

  List<int> _sortCluster(List<Map<String, dynamic>> data, List<int> cluster) {
    final keys = _keys(style.citation);
    if (keys.isEmpty || cluster.length < 2) return cluster;
    return _sorted(data, cluster, keys, bibliography: false);
  }

  List<int> _sorted(
    List<Map<String, dynamic>> data,
    List<int> idx,
    List<XmlElement> keys, {
    required bool bibliography,
  }) {
    final table = <int, List<String>>{
      for (final i in idx)
        i: [
          for (final k in keys)
            _normalize(
              engine.sortKey(
                CslContext(data[i], bibliography: bibliography, sort: true),
                macro: k.getAttribute('macro'),
                variable: k.getAttribute('variable'),
              ),
            ),
        ],
    };
    final pos = {for (final (n, i) in idx.indexed) i: n};
    final out = [...idx];
    out.sort((a, b) {
      for (var n = 0; n < keys.length; n++) {
        final x = table[a]![n], y = table[b]![n];
        if (x == y) continue;
        if (x.isEmpty) return 1;
        if (y.isEmpty) return -1;
        final c = x.compareTo(y);
        return keys[n].getAttribute('sort') == 'descending' ? -c : c;
      }
      return pos[a]!.compareTo(pos[b]!);
    });
    return out;
  }

  static const _from = 'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿšžłćńśźż';
  static const _to = 'aaaaaaaceeeeiiiinoooooouuuuyyszlcnszz';

  String _normalize(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      final i = _from.indexOf(ch);
      b.write(i >= 0 ? _to[i] : ch);
    }
    return b
        .toString()
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '')
        .replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(8, '0'))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ------------------------------------------------------ disambiguation

  void _disambiguate(
    List<Map<String, dynamic>> data,
    List<_State> states,
    List<int> order,
  ) {
    final c = style.citation;
    bool on(String a) => c?.getAttribute(a) == 'true';
    final addNames = on('disambiguate-add-names');
    final addGiven = on('disambiguate-add-givenname');
    final addYear = on('disambiguate-add-year-suffix');
    if (!addNames && !addGiven && !addYear) return;
    if (style.numeric || data.length < 2) return;

    String cite(int i) => engine
        .citationItem(
          CslContext(
            data[i],
            yearSuffix: states[i].suffix,
            etAlUseFirst: states[i].useFirst,
            fullNames: states[i].full,
          ),
        )
        .plain;

    List<List<int>> groups() {
      final by = <String, List<int>>{};
      for (var i = 0; i < data.length; i++) {
        (by[cite(i)] ??= []).add(i);
      }
      return [
        for (final g in by.values)
          if (g.length > 1) g,
      ];
    }

    bool distinct(List<int> g) => g.map(cite).toSet().length == g.length;

    if (addNames) {
      for (final g in groups()) {
        final most = g
            .map((i) => (data[i]['author'] as List?)?.length ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b);
        for (var k = 2; k <= most; k++) {
          for (final i in g) {
            states[i].useFirst = k;
          }
          if (distinct(g)) break;
        }
        if (!distinct(g)) {
          for (final i in g) {
            states[i].useFirst = null;
          }
        }
      }
    }
    if (addGiven) {
      for (final g in groups()) {
        final before = g.map(cite).toList();
        for (final i in g) {
          states[i].full = true;
        }
        final after = g.map(cite).toList();
        // Keep given names only if they tell more of the group apart.
        if (after.toSet().length <= before.toSet().length) {
          for (final i in g) {
            states[i].full = false;
          }
        }
      }
    }
    if (addYear) {
      for (final g in groups()) {
        final inBib = [...g]
          ..sort((a, b) => order.indexOf(a) - order.indexOf(b));
        // Members that the earlier steps already told apart need none.
        final strings = {for (final i in g) i: cite(i)};
        final counts = <String, int>{};
        for (final s in strings.values) {
          counts[s] = (counts[s] ?? 0) + 1;
        }
        var n = 0;
        for (final i in inBib) {
          if (counts[strings[i]]! > 1) states[i].suffix = _letters(n++);
        }
      }
    }
  }

  static String _letters(int n) {
    var s = '';
    var x = n;
    do {
      s = String.fromCharCode(97 + x % 26) + s;
      x = x ~/ 26 - 1;
    } while (x >= 0);
    return s;
  }
}
