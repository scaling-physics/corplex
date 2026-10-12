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
  /// entries (a single reference shown on its own).
  CslOutput process(
    List<Map<String, dynamic>> items, {
    List<List<int>> clusters = const [],
    bool suppressNumbers = false,
  }) {
    final data = [
      for (final (i, it) in items.indexed) {...it, 'citation-number': i + 1},
    ];
    final order = _bibliographyOrder(data);
    final states = [for (final _ in data) _State()];
    _disambiguate(data, states, order);

    CslContext ctxFor(int i, {bool bib = false, String position = 'first'}) =>
        CslContext(
          data[i],
          bibliography: bib,
          suppressNumber: suppressNumbers,
          yearSuffix: states[i].suffix,
          etAlUseFirst: bib ? null : states[i].useFirst,
          fullNames: !bib && states[i].full,
          position: position,
        );

    final bibliography = [
      for (final i in order) engine.bibliographyEntry(ctxFor(i, bib: true)),
    ];

    final seen = <int>{};
    final citations = <CslRich>[];
    final layout = style.citationLayout;
    final delimiter = layout?.getAttribute('delimiter') ?? '';
    final collapse = style.citation?.getAttribute('collapse');
    for (final cluster in clusters) {
      final sorted = _sortCluster(data, cluster);
      final rendered = <CslRich>[];
      for (final i in sorted) {
        rendered.add(
          engine.citationItem(
            ctxFor(i, position: seen.contains(i) ? 'subsequent' : 'first'),
          ),
        );
      }
      seen.addAll(cluster);
      final spans = <CslSpan>[];
      void add(List<CslSpan> s, {String joiner = ''}) {
        if (spans.isNotEmpty && joiner.isNotEmpty) spans.add(CslSpan(joiner));
        spans.addAll(s);
      }

      var k = 0;
      while (k < sorted.length) {
        if (collapse == 'citation-number') {
          var end = k;
          while (end + 1 < sorted.length &&
              (data[sorted[end + 1]]['citation-number'] as int) ==
                  (data[sorted[end]]['citation-number'] as int) + 1) {
            end++;
          }
          if (end - k >= 2) {
            add(rendered[k].spans, joiner: delimiter);
            spans.add(const CslSpan('–'));
            spans.addAll(rendered[end].spans);
            k = end + 1;
            continue;
          }
        }
        add(rendered[k].spans, joiner: delimiter);
        k++;
      }
      citations.add(
        engine.wrapCitation(spans, ctxFor(cluster.isEmpty ? 0 : cluster.first)),
      );
    }
    return CslOutput(
      citations: citations,
      bibliography: bibliography,
      bibliographyOrder: order,
    );
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
