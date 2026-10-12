import 'package:xml/xml.dart';

import 'csl_locale.dart';
import 'csl_rich.dart';
import 'csl_style.dart';
import 'csl_text.dart';

/// The names variables of CSL.
const cslNameVariables = {
  'author',
  'editor',
  'translator',
  'container-author',
  'collection-editor',
  'composer',
  'director',
  'interviewer',
  'recipient',
  'reviewed-author',
  'illustrator',
  'original-author',
  'editorial-director',
  'compiler',
  'chair',
  'contributor',
  'curator',
  'executive-producer',
  'guest',
  'host',
  'narrator',
  'organizer',
  'performer',
  'producer',
  'script-writer',
  'series-creator',
  'editor-translator',
};

const cslDateVariables = {
  'issued',
  'accessed',
  'event-date',
  'original-date',
  'submitted',
  'available-date',
};

/// What one render of one item needs besides the item itself.
class CslContext {
  CslContext(
    this.item, {
    this.bibliography = false,
    this.sort = false,
    this.suppressNumber = false,
    this.yearSuffix,
    this.etAlUseFirst,
    this.fullNames = false,
    this.position = 'first',
    this.locator,
  });

  /// CSL-JSON, plus `citation-number`.
  final Map<String, dynamic> item;
  final bool bibliography;

  /// Render sort keys instead of display text.
  final bool sort;

  /// Leave `citation-number` out (a single reference without a list).
  final bool suppressNumber;
  final String? yearSuffix;

  /// Disambiguation: show this many names before "et al.".
  final int? etAlUseFirst;

  /// Disambiguation: show given names.
  final bool fullNames;
  final String position;
  final String? locator;

  final suppressed = <String>{};
  final emitted = <String>{};
  XmlElement? scope;
}

class _Out {
  _Out([List<CslSpan>? s]) : spans = s ?? [];
  final List<CslSpan> spans;
  bool called = false;
  bool got = false;

  bool get isEmpty {
    for (final s in spans) {
      if (s.text.isNotEmpty) return false;
    }
    return true;
  }

  String get plain => spans.map((s) => s.text).join();

  void merge(_Out o) {
    called = called || o.called;
    got = got || o.got;
  }
}

class _Name {
  _Name(Map m)
    : family = (m['family'] ?? '').toString(),
      given = (m['given'] ?? '').toString(),
      particle = (m['non-dropping-particle'] ?? '').toString(),
      literal = m['literal']?.toString();
  final String family;
  final String given;
  final String particle;
  final String? literal;
}

/// Renders CSL elements for one item at a time.
class CslEngine {
  CslEngine(this.style) : locale = style.locale;

  final CslStyle style;
  final CslLocale locale;

  // ---------------------------------------------------------------- API

  /// The entry for [ctx].item in the bibliography layout.
  CslRich bibliographyEntry(CslContext ctx) {
    final layout = style.bibliographyLayout;
    if (layout == null) return CslRich.empty;
    ctx.scope = style.bibliography;
    return _finish(_layout(layout, ctx));
  }

  /// One item's text in the citation layout (no cluster affixes).
  CslRich citationItem(CslContext ctx, {bool withAffixes = false}) {
    final layout = style.citationLayout;
    if (layout == null) return CslRich.empty;
    ctx.scope = style.citation;
    final o = _children(layout.childElements, ctx);
    return _finish(withAffixes ? _fmt(layout, o, ctx) : o);
  }

  /// The citation layout's affixes and formatting around [inner].
  CslRich wrapCitation(List<CslSpan> inner, CslContext ctx) {
    final layout = style.citationLayout;
    if (layout == null) return CslRich(inner);
    return _finish(_fmt(layout, _Out(inner), ctx));
  }

  /// A key for sorting: the text of macro [macro] or variable [variable].
  String sortKey(CslContext ctx, {String? macro, String? variable}) {
    ctx.scope = style.bibliography ?? style.citation;
    if (macro != null) {
      final m = style.macros[macro];
      if (m == null) return '';
      return _children(m.childElements, ctx).plain;
    }
    if (variable != null) {
      return _variableSort(variable, ctx);
    }
    return '';
  }

  CslRich _finish(_Out o) => CslRich(_merge(o.spans));

  // ------------------------------------------------------------ layout

  _Out _layout(XmlElement layout, CslContext ctx) {
    final aligned = style.bibliography?.getAttribute('second-field-align');
    if (aligned != null) {
      // A number in the margin, then the entry: keep a space between.
      final kids = layout.childElements.toList();
      if (kids.isNotEmpty) {
        final head = _render(kids.first, ctx);
        final rest = _children(kids.skip(1), ctx);
        final o = _Out()
          ..merge(head)
          ..merge(rest);
        _append(o.spans, head.spans);
        if (!head.isEmpty) _append(o.spans, [const CslSpan(' ')]);
        _append(o.spans, rest.spans);
        return _fmt(layout, o, ctx);
      }
    }
    final o = _children(layout.childElements, ctx);
    return _fmt(layout, o, ctx);
  }

  _Out _children(
    Iterable<XmlElement> kids,
    CslContext ctx, {
    String delimiter = '',
  }) {
    final out = _Out();
    var first = true;
    for (final k in _expand(kids, ctx)) {
      final r = _render(k, ctx);
      out.merge(r);
      if (r.isEmpty) continue;
      if (!first && delimiter.isNotEmpty) {
        _append(out.spans, [CslSpan(delimiter)]);
      }
      _append(out.spans, r.spans);
      first = false;
    }
    return out;
  }

  /// `choose` is transparent: the elements of the chosen branch take its
  /// place, so a parent group's delimiter falls between them.
  Iterable<XmlElement> _expand(
    Iterable<XmlElement> kids,
    CslContext ctx,
  ) sync* {
    for (final k in kids) {
      if (k.name.local != 'choose') {
        yield k;
        continue;
      }
      for (final b in k.childElements) {
        final n = b.name.local;
        if (n == 'else' || ((n == 'if' || n == 'else-if') && _test(b, ctx))) {
          yield* _expand(b.childElements, ctx);
          break;
        }
      }
    }
  }

  // ------------------------------------------------------------ dispatch

  _Out _render(XmlElement e, CslContext ctx) {
    switch (e.name.local) {
      case 'text':
        return _text(e, ctx);
      case 'group':
        return _group(e, ctx);
      case 'choose':
        return _choose(e, ctx);
      case 'names':
        return _names(e, ctx);
      case 'date':
        return _date(e, ctx);
      case 'number':
        return _number(e, ctx);
      case 'label':
        return _label(e, ctx);
    }
    return _Out();
  }

  // ----------------------------------------------------------- group/choose

  _Out _group(XmlElement e, CslContext ctx) {
    final o = _children(
      e.childElements,
      ctx,
      delimiter: ctx.sort ? ' ' : e.getAttribute('delimiter') ?? '',
    );
    if (o.isEmpty || (o.called && !o.got)) {
      final empty = _Out();
      empty.called = o.called;
      empty.got = o.got;
      return empty;
    }
    return _fmt(e, o, ctx);
  }

  _Out _choose(XmlElement e, CslContext ctx) {
    for (final b in e.childElements) {
      final n = b.name.local;
      if (n == 'else' || ((n == 'if' || n == 'else-if') && _test(b, ctx))) {
        return _children(b.childElements, ctx);
      }
    }
    return _Out();
  }

  bool _test(XmlElement c, CslContext ctx) {
    final results = <bool>[];
    List<String> list(String a) => (c.getAttribute(a) ?? '')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    for (final v in list('type')) {
      results.add(ctx.item['type'] == v);
    }
    for (final v in list('variable')) {
      results.add(_hasVariable(v, ctx));
    }
    for (final v in list('is-numeric')) {
      final val = _stringValue(v, ctx);
      results.add(val != null && isNumericValue(val));
    }
    for (final v in list('is-uncertain-date')) {
      final d = ctx.item[v];
      results.add(d is Map && d['circa'] == true);
    }
    for (final _ in list('locator')) {
      results.add(false);
    }
    for (final v in list('position')) {
      results.add(switch (v) {
        'first' => ctx.position == 'first',
        'subsequent' => ctx.position != 'first',
        _ => false,
      });
    }
    for (final _ in list('disambiguate')) {
      results.add(false);
    }
    final match = c.getAttribute('match') ?? 'all';
    if (results.isEmpty) return false;
    return switch (match) {
      'any' => results.any((r) => r),
      'none' => !results.any((r) => r),
      _ => results.every((r) => r),
    };
  }

  bool _hasVariable(String v, CslContext ctx) {
    if (ctx.suppressed.contains(v)) return false;
    if (v == 'citation-number') {
      return !ctx.suppressNumber && ctx.item['citation-number'] != null;
    }
    if (v == 'year-suffix') return ctx.yearSuffix != null;
    if (v == 'locator') return ctx.locator != null;
    final val = ctx.item[v];
    if (val == null) return false;
    if (val is String) return val.trim().isNotEmpty;
    if (val is List) return val.isNotEmpty;
    if (val is Map) {
      if (cslDateVariables.contains(v)) {
        final parts = val['date-parts'];
        return (parts is List && parts.isNotEmpty) ||
            (val['literal']?.toString().isNotEmpty ?? false);
      }
      return val.isNotEmpty;
    }
    return true;
  }

  String? _stringValue(String v, CslContext ctx) {
    if (ctx.suppressed.contains(v)) return null;
    if (v == 'citation-number') return ctx.item['citation-number']?.toString();
    if (v == 'locator') return ctx.locator;
    final val = ctx.item[v];
    if (val == null || val is Map || val is List) return null;
    final s = val.toString();
    return s.isEmpty ? null : s;
  }

  // ------------------------------------------------------------------ text

  _Out _text(XmlElement e, CslContext ctx) {
    final macro = e.getAttribute('macro');
    if (macro != null) {
      final m = style.macros[macro];
      if (m == null) return _Out();
      final o = _children(m.childElements, ctx);
      return _fmt(e, o, ctx);
    }
    final variable = e.getAttribute('variable');
    if (variable != null) {
      // An empty year suffix never suppresses its group (it is usually
      // absent, and "n.d." beside it must still print).
      final o = _Out()..called = variable != 'year-suffix';
      if (ctx.suppressed.contains(variable)) return o;
      var v = _textVariable(variable, e.getAttribute('form'), ctx);
      if (v == null || v.isEmpty) return o;
      if (variable == 'page') {
        v = formatPages(v, style.option('page-range-format'));
      }
      o.got = true;
      ctx.emitted.add(variable);
      o.spans.add(CslSpan(v));
      return _fmt(e, o, ctx);
    }
    final term = e.getAttribute('term');
    if (term != null) {
      final plural = e.getAttribute('plural') == 'true';
      final t = locale.term(
        term,
        form: e.getAttribute('form') ?? 'long',
        plural: plural,
      );
      if (t == null || t.isEmpty) return _Out();
      return _fmt(e, _Out([CslSpan(t)]), ctx);
    }
    final value = e.getAttribute('value');
    if (value != null) return _fmt(e, _Out([CslSpan(value)]), ctx);
    return _Out();
  }

  String? _textVariable(String v, String? form, CslContext ctx) {
    switch (v) {
      case 'citation-number':
        return ctx.suppressNumber
            ? null
            : ctx.item['citation-number']?.toString();
      case 'year-suffix':
        return ctx.yearSuffix;
      case 'locator':
        return ctx.locator;
    }
    if (form == 'short') {
      final s = ctx.item['$v-short'];
      if (s != null && s.toString().isNotEmpty) return s.toString();
    }
    final val = ctx.item[v];
    if (val == null || val is Map || val is List) return null;
    return val.toString().trim();
  }

  String _variableSort(String v, CslContext ctx) {
    if (cslNameVariables.contains(v)) {
      final names = ctx.item[v];
      if (names is List) {
        return names.whereType<Map>().map((m) => _sortName(_Name(m))).join(' ');
      }
      return '';
    }
    if (cslDateVariables.contains(v)) return _dateSort(ctx.item[v]);
    final s = _textVariable(v, null, ctx);
    return s ?? '';
  }

  String _dateSort(Object? d) {
    if (d is! Map) return '';
    final parts = d['date-parts'];
    if (parts is! List || parts.isEmpty || parts.first is! List) return '';
    String two(Object? x) =>
        (int.tryParse('$x') ?? 0).toString().padLeft(2, '0');
    String key(List p) =>
        '${(int.tryParse('${p.isNotEmpty ? p[0] : 0}') ?? 0).toString().padLeft(4, '0')}'
        '${two(p.length > 1 ? p[1] : 0)}${two(p.length > 2 ? p[2] : 0)}';
    return key(parts.first as List);
  }

  // ---------------------------------------------------------------- number

  _Out _number(XmlElement e, CslContext ctx) {
    final v = e.getAttribute('variable') ?? '';
    final o = _Out()..called = true;
    final raw = _stringValue(v, ctx);
    if (raw == null) return o;
    o.got = true;
    ctx.emitted.add(v);
    final form = e.getAttribute('form') ?? 'numeric';
    var text = raw;
    if (isNumericValue(raw)) {
      text = raw
          .replaceAllMapped(RegExp(r'(\d+)|([,&\-–])'), (m) {
            if (m[1] != null) {
              final n = int.parse(m[1]!);
              return switch (form) {
                'ordinal' => '$n${locale.ordinalSuffix(n)}',
                'long-ordinal' =>
                  (n >= 1 && n <= 10
                          ? locale.term(
                              'long-ordinal-${n.toString().padLeft(2, '0')}',
                            )
                          : null) ??
                      '$n${locale.ordinalSuffix(n)}',
                'roman' => romanNumeral(n),
                _ => '$n',
              };
            }
            return switch (m[2]) {
              ',' => ', ',
              '&' => ' & ',
              _ => '–',
            };
          })
          .replaceAll(RegExp(r',\s{2,}'), ', ');
    }
    o.spans.add(CslSpan(text));
    return _fmt(e, o, ctx);
  }

  // ----------------------------------------------------------------- label

  _Out _label(XmlElement e, CslContext ctx) {
    final v = e.getAttribute('variable') ?? '';
    final raw = _stringValue(v, ctx);
    if (raw == null) return _Out();
    final plural = _labelPlural(e, v, raw, null);
    final termName = switch (v) {
      'number-of-pages' => 'page',
      'number-of-volumes' => 'volume',
      'chapter-number' => 'chapter',
      'collection-number' => 'collection-number',
      _ => v,
    };
    return _termLabel(e, termName, plural, ctx);
  }

  bool _labelPlural(XmlElement e, String variable, String raw, int? nameCount) {
    final p = e.getAttribute('plural') ?? 'contextual';
    if (p == 'always') return true;
    if (p == 'never') return false;
    if (nameCount != null) return nameCount > 1;
    if (variable.startsWith('number-of')) return raw.trim() != '1';
    return RegExp(r'[,&\-–]').hasMatch(raw) && isNumericValue(raw);
  }

  _Out _termLabel(XmlElement e, String term, bool plural, CslContext ctx) {
    final t = locale.term(
      term,
      form: e.getAttribute('form') ?? 'long',
      plural: plural,
    );
    if (t == null || t.isEmpty) return _Out();
    return _fmt(e, _Out([CslSpan(t)]), ctx);
  }

  // ----------------------------------------------------------------- names

  List<_Name> _namesOf(String v, CslContext ctx) {
    final l = ctx.item[v];
    if (l is! List) return const [];
    return [for (final m in l.whereType<Map>()) _Name(m)];
  }

  String? _opt(String name, XmlElement? nameEl, CslContext ctx) =>
      nameEl?.getAttribute(name) ??
      ctx.scope?.getAttribute(name) ??
      style.root.getAttribute(name);

  _Out _names(
    XmlElement e,
    CslContext ctx, {
    XmlElement? inheritName,
    XmlElement? inheritEtAl,
    XmlElement? inheritLabel,
    bool inheritLabelFirst = false,
  }) {
    final vars = (e.getAttribute('variable') ?? '')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final out = _Out()..called = vars.isNotEmpty;
    XmlElement? child(String n) =>
        e.childElements.where((c) => c.name.local == n).firstOrNull;
    final nameEl = child('name') ?? inheritName;
    final etAlEl = child('et-al') ?? inheritEtAl;
    final labelEl = child('label') ?? inheritLabel;
    final kids = e.childElements.toList();
    final labelFirst = child('label') != null
        ? kids.indexOf(child('label')!) <
              (child('name') == null ? 1 << 30 : kids.indexOf(child('name')!))
        : inheritLabelFirst;

    final pieces = <_Out>[];
    for (final v in vars) {
      if (ctx.suppressed.contains(v)) continue;
      final list = _namesOf(v, ctx);
      if (list.isEmpty) continue;
      final piece = _nameList(
        v,
        list,
        nameEl,
        etAlEl,
        labelEl,
        labelFirst,
        ctx,
        forcedEtAl: ctx.item['_etAl:$v'] == true,
      );
      if (piece.isEmpty) continue;
      ctx.emitted.add(v);
      pieces.add(piece);
    }
    if (pieces.isNotEmpty) {
      out.got = true;
      final delim = ctx.sort
          ? ' '
          : e.getAttribute('delimiter') ??
                style.root.getAttribute('names-delimiter') ??
                ctx.scope?.getAttribute('names-delimiter') ??
                '';
      for (var i = 0; i < pieces.length; i++) {
        if (i > 0 && delim.isNotEmpty) _append(out.spans, [CslSpan(delim)]);
        _append(out.spans, pieces[i].spans);
      }
      return _fmt(e, out, ctx);
    }
    final sub = child('substitute');
    if (sub != null) {
      for (final c in sub.childElements) {
        final before = {...ctx.emitted};
        final _Out r;
        if (c.name.local == 'names') {
          r = _names(
            c,
            ctx,
            inheritName: nameEl,
            inheritEtAl: etAlEl,
            inheritLabel: labelEl,
            inheritLabelFirst: labelFirst,
          );
        } else {
          r = _render(c, ctx);
        }
        out.merge(r);
        if (!r.isEmpty) {
          ctx.suppressed.addAll(ctx.emitted.difference(before));
          out.spans.addAll(r.spans);
          out.got = true;
          // The parent's formatting applies to what stepped in.
          final f = _fmt(e, out, ctx);
          return f;
        }
      }
    }
    return out;
  }

  _Out _nameList(
    String variable,
    List<_Name> list,
    XmlElement? nameEl,
    XmlElement? etAlEl,
    XmlElement? labelEl,
    bool labelFirst,
    CslContext ctx, {
    bool forcedEtAl = false,
  }) {
    String? o(String n) => _opt(n, nameEl, ctx);
    final delim =
        nameEl?.getAttribute('delimiter') ??
        ctx.scope?.getAttribute('name-delimiter') ??
        style.root.getAttribute('name-delimiter') ??
        ', ';
    final n = list.length;
    final min = int.tryParse(o('et-al-min') ?? o('names-min') ?? '');
    var useFirst = int.tryParse(
      o('et-al-use-first') ?? o('names-use-first') ?? '',
    );
    final useLast = (o('et-al-use-last') ?? o('names-use-last')) == 'true';

    var truncated = forcedEtAl;
    if (min != null && n >= min) truncated = true;
    if (ctx.etAlUseFirst != null && n > ctx.etAlUseFirst!) {
      truncated = true;
      useFirst = ctx.etAlUseFirst;
    }
    if (ctx.sort) truncated = false;
    useFirst ??= truncated && !forcedEtAl ? 1 : n;
    if (useFirst > n) useFirst = n;

    final form = ctx.fullNames
        ? 'long'
        : (nameEl?.getAttribute('form') ?? 'long');
    final asSort = o('name-as-sort-order');
    final initWith = o('initialize-with');
    final initialize = o('initialize') != 'false';
    final sep = o('sort-separator') ?? ', ';
    final hyphen = style.root.getAttribute('initialize-with-hyphen') != 'false';
    final demote =
        style.root.getAttribute('demote-non-dropping-particle') ??
        'display-and-sort';

    String render(_Name nm, int index) {
      if (ctx.sort) return _sortName(nm);
      return _nameString(
        nm,
        form: form,
        inverted: asSort == 'all' || (asSort == 'first' && index == 0),
        initWith: initWith,
        initialize: initialize,
        sep: sep,
        hyphen: hyphen,
        demote: demote,
      );
    }

    final strings = <String>[];
    final inverted = <bool>[];
    final bool ellipsis = truncated && useLast && n > useFirst + 1;
    final shown = truncated ? list.take(useFirst).toList() : list;
    for (var i = 0; i < shown.length; i++) {
      strings.add(render(shown[i], i));
      inverted.add(asSort == 'all' || (asSort == 'first' && i == 0));
    }
    if (ellipsis) {
      strings.add(render(list.last, n - 1));
      inverted.add(asSort == 'all');
    }

    final res = _Out();
    final k = strings.length;
    if (ctx.sort) {
      res.spans.add(CslSpan(strings.join(' ')));
    } else if (truncated && ellipsis) {
      res.spans.add(
        CslSpan('${strings.take(k - 1).join(delim)}$delim… ${strings.last}'),
      );
    } else if (truncated) {
      res.spans.add(CslSpan(strings.join(delim)));
      final dp = o('delimiter-precedes-et-al') ?? 'contextual';
      final precede = switch (dp) {
        'always' => true,
        'never' => false,
        'after-inverted-name' => inverted.isNotEmpty && inverted.last,
        _ => k >= 2,
      };
      _append(res.spans, [CslSpan(precede ? delim : ' ')]);
      final etName = etAlEl?.getAttribute('term') ?? 'et-al';
      final et = locale.term(
        etName,
        form: etAlEl?.getAttribute('form') ?? 'long',
      );
      _append(
        res.spans,
        etAlEl != null
            ? _fmt(etAlEl, _Out([CslSpan(et ?? 'et al.')]), ctx).spans
            : [CslSpan(et ?? 'et al.')],
      );
    } else {
      final and = o('and');
      if (and != null && k > 1) {
        final andText = and == 'symbol'
            ? (locale.term('and', form: 'symbol') ?? '&')
            : (locale.term('and') ?? 'and');
        final dpl = o('delimiter-precedes-last') ?? 'contextual';
        final precede = switch (dpl) {
          'always' => true,
          'never' => false,
          'after-inverted-name' => inverted[k - 2],
          _ => k >= 3,
        };
        res.spans.add(
          CslSpan(
            '${strings.take(k - 1).join(delim)}${precede ? delim : ' '}'
            '$andText ${strings.last}',
          ),
        );
      } else {
        res.spans.add(CslSpan(strings.join(delim)));
      }
    }

    var out = res;
    if (nameEl != null && !ctx.sort) out = _fmt(nameEl, res, ctx);
    if (labelEl != null && !ctx.sort) {
      final plural = _labelPlural(labelEl, variable, '', list.length);
      final l = _termLabel(labelEl, variable, plural, ctx);
      if (!l.isEmpty) {
        final both = _Out();
        if (labelFirst) {
          _append(both.spans, l.spans);
          _append(both.spans, out.spans);
        } else {
          _append(both.spans, out.spans);
          _append(both.spans, l.spans);
        }
        out = both;
      }
    }
    return out;
  }

  String _sortName(_Name n) {
    if (n.literal != null) return n.literal!;
    final demote =
        style.root.getAttribute('demote-non-dropping-particle') ??
        'display-and-sort';
    final fam = demote == 'never' && n.particle.isNotEmpty
        ? '${n.particle} ${n.family}'
        : n.family;
    return [fam, n.given].where((s) => s.isNotEmpty).join(' ');
  }

  String _initials(
    String given,
    String initWith,
    bool initialize,
    bool hyphen,
  ) {
    final core = initWith.trimRight();
    final gap = initWith.substring(core.length);
    final tokens = given.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final out = StringBuffer();
    for (final t in tokens) {
      // "J.R." is two initials, "J." one.
      final dotted = RegExp(r'^([^\W\d_]\.)+$', unicode: true).hasMatch(t);
      final isInitial =
          dotted || RegExp(r'^[^\W\d_]\.?$', unicode: true).hasMatch(t);
      if (!initialize && !isInitial) {
        out.write('$t ');
        continue;
      }
      final parts = dotted
          ? t.split('.').where((p) => p.isNotEmpty).toList()
          : t.split('-').where((p) => p.isNotEmpty).toList();
      String first(String p) => String.fromCharCode(p.runes.first);
      if (dotted) {
        for (final p in parts) {
          out.write('${first(p)}$core$gap');
        }
      } else if (hyphen && parts.length > 1) {
        out.write('${parts.map((p) => '${first(p)}$core').join('-')}$gap');
      } else {
        for (final p in parts) {
          out.write('${first(p)}$core$gap');
        }
      }
    }
    return out.toString().trimRight();
  }

  String _nameString(
    _Name n, {
    required String form,
    required bool inverted,
    required String? initWith,
    required bool initialize,
    required String sep,
    required bool hyphen,
    required String demote,
  }) {
    if (n.literal != null) return n.literal!;
    final fam = n.particle.isEmpty ? n.family : '${n.particle} ${n.family}';
    if (form == 'short') return fam;
    final given = n.given.isEmpty
        ? ''
        : initWith != null
        ? _initials(n.given, initWith, initialize, hyphen)
        : n.given;
    if (given.isEmpty) return fam;
    if (inverted) {
      final demoted = demote == 'display-and-sort' && n.particle.isNotEmpty;
      final head = demoted ? n.family : fam;
      final tail = demoted ? '$given ${n.particle}' : given;
      return '$head$sep$tail';
    }
    return '$given $fam';
  }

  // ------------------------------------------------------------------ date

  _Out _date(XmlElement e, CslContext ctx) {
    final v = e.getAttribute('variable') ?? '';
    final o = _Out()..called = true;
    if (!_hasVariable(v, ctx)) return o;
    final d = ctx.item[v] as Map;
    o.got = true;
    ctx.emitted.add(v);
    if (ctx.sort) {
      o.spans.add(CslSpan(_dateSort(d)));
      return o;
    }
    final literal = d['literal']?.toString();
    final parts = d['date-parts'];
    if (literal != null &&
        literal.isNotEmpty &&
        (parts is! List || parts.isEmpty)) {
      o.spans.add(CslSpan(literal));
      return _fmt(e, o, ctx);
    }
    final ranges = (parts as List).whereType<List>().toList();
    final form = e.getAttribute('form');
    final filter =
        e.getAttribute('date-parts') ??
        (form == null ? 'year-month-day' : 'year-month-day');
    final bool addSuffix =
        ctx.yearSuffix != null && !style.hasYearSuffixVariable && v == 'issued';

    List<XmlElement> partEls;
    if (form != null && locale.dateForms.containsKey(form)) {
      final base = locale.dateForms[form]!;
      final overrides = {
        for (final p in e.childElements.where(
          (c) => c.name.local == 'date-part',
        ))
          p.getAttribute('name') ?? '': p,
      };
      partEls = [
        for (final p in base.childElements.where(
          (c) => c.name.local == 'date-part',
        ))
          overrides[p.getAttribute('name')] != null
              ? _mergeParts(p, overrides[p.getAttribute('name')]!)
              : p,
      ];
    } else {
      partEls = e.childElements
          .where((c) => c.name.local == 'date-part')
          .toList();
    }
    final delim = e.getAttribute('delimiter') ?? '';
    final wanted = switch (filter) {
      'year' => {'year'},
      'year-month' => {'year', 'month'},
      _ => {'year', 'month', 'day'},
    };

    _Out renderOne(List dp) {
      final r = _Out();
      int? at(int i) => i < dp.length ? int.tryParse('${dp[i]}') : null;
      final year = at(0), month = at(1), day = at(2);
      var firstPart = true;
      for (final p in partEls) {
        final name = p.getAttribute('name');
        if (!wanted.contains(name)) continue;
        String? text;
        switch (name) {
          case 'year':
            if (year != null) {
              final f = p.getAttribute('form');
              text = f == 'short'
                  ? (year % 100).toString().padLeft(2, '0')
                  : year.toString();
            }
          case 'month':
            if (month != null) {
              final f = p.getAttribute('form') ?? 'long';
              if (f == 'numeric') {
                text = '$month';
              } else if (f == 'numeric-leading-zeros') {
                text = month.toString().padLeft(2, '0');
              } else {
                final key = month > 12
                    ? 'season-${(month - 12).toString().padLeft(2, '0')}'
                    : 'month-${month.toString().padLeft(2, '0')}';
                text = locale.term(key, form: f == 'short' ? 'short' : 'long');
              }
            }
          case 'day':
            if (day != null) {
              final f = p.getAttribute('form') ?? 'numeric';
              text = switch (f) {
                'numeric-leading-zeros' => day.toString().padLeft(2, '0'),
                'ordinal' => '$day${locale.ordinalSuffix(day)}',
                _ => '$day',
              };
            }
        }
        if (text == null || text.isEmpty) continue;
        var part = _Out([CslSpan(text)]);
        if (name == 'year' && addSuffix) {
          part.spans.add(CslSpan(ctx.yearSuffix!));
        }
        part = _fmt(p, part, ctx);
        if (!firstPart && delim.isNotEmpty) _append(r.spans, [CslSpan(delim)]);
        _append(r.spans, part.spans);
        firstPart = false;
      }
      return r;
    }

    if (ranges.isEmpty) return o;
    final first = renderOne(ranges.first);
    _append(o.spans, first.spans);
    if (ranges.length > 1) {
      final last = renderOne(ranges[1]);
      if (!last.isEmpty) {
        _append(o.spans, [const CslSpan('–')]);
        _append(o.spans, last.spans);
      }
    }
    if (d['circa'] == true) {
      final c = locale.term('circa', form: 'short') ?? 'ca.';
      o.spans.insert(0, CslSpan('$c '));
    }
    return _fmt(e, o, ctx);
  }

  XmlElement _mergeParts(XmlElement base, XmlElement over) {
    final merged = base.copy();
    for (final a in over.attributes) {
      merged.setAttribute(a.name.local, a.value);
    }
    return merged;
  }

  // ------------------------------------------------------------ formatting

  /// Applies the formatting and affixes of [e] to [body].
  _Out _fmt(XmlElement e, _Out body, CslContext ctx) {
    if (body.isEmpty || ctx.sort) return body;
    var spans = [...body.spans];
    final tc = e.getAttribute('text-case');
    if (tc != null) spans = caseSpans(spans, tc);
    if (e.getAttribute('strip-periods') == 'true') {
      spans = [for (final s in spans) s.withText(stripPeriods(s.text))];
    }
    final fs = e.getAttribute('font-style');
    final fv = e.getAttribute('font-variant');
    final fw = e.getAttribute('font-weight');
    final td = e.getAttribute('text-decoration');
    final va = e.getAttribute('vertical-align');
    if (fs != null || fv != null || fw != null || td != null || va != null) {
      spans = [
        for (final s in spans)
          s.copyWith(
            italic: fs == null ? null : (fs == 'italic' || fs == 'oblique'),
            smallCaps: fv == null ? null : fv == 'small-caps',
            bold: fw == null ? null : fw == 'bold',
            underline: td == null ? null : td == 'underline',
            vAlign: va == null
                ? null
                : va == 'sup'
                ? 1
                : va == 'sub'
                ? -1
                : 0,
          ),
      ];
    }
    final prefix = e.getAttribute('prefix');
    final suffix = e.getAttribute('suffix');
    final quotes = e.getAttribute('quotes') == 'true';
    final res = <CslSpan>[];
    if (prefix != null && prefix.isNotEmpty) res.add(CslSpan(prefix));
    if (quotes) {
      _append(res, [CslSpan(locale.openQuote)]);
      // Inside the quote spans, the closing quote comes after; trailing
      // punctuation of the suffix moves inside (en-US).
      _append(res, spans);
      _append(res, [CslSpan(locale.closeQuote)]);
    } else {
      _append(res, spans);
    }
    if (suffix != null && suffix.isNotEmpty) _append(res, [CslSpan(suffix)]);
    return _Out(res)
      ..called = body.called
      ..got = body.got;
  }

  // ------------------------------------------------------------ joining

  /// Appends [add] to [into], collapsing doubled punctuation and moving
  /// `.`/`,` inside a closing quote (en-US).
  void _append(List<CslSpan> into, List<CslSpan> add) {
    for (var span in add) {
      if (span.text.isEmpty) continue;
      if (into.isNotEmpty) {
        final last = into.last;
        var t = span.text;
        final lt = last.text;
        final c = t[0];
        if (lt.isNotEmpty) {
          final close = locale.closeQuote;
          if (locale.punctuationInQuote &&
              lt.endsWith(close) &&
              (c == ',' || c == '.')) {
            final inner = lt.substring(0, lt.length - close.length);
            if (!inner.endsWith(c)) {
              into[into.length - 1] = last.withText('$inner$c$close');
            }
            t = t.substring(1);
          } else if ((c == '.' && RegExp(r'[.!?]$').hasMatch(lt)) ||
              (c == ',' && lt.endsWith(',')) ||
              (c == ';' && lt.endsWith(';')) ||
              (c == ':' && lt.endsWith(':'))) {
            t = t.substring(1);
          }
          if (t.isNotEmpty && t[0] == ' ' && into.last.text.endsWith(' ')) {
            t = t.substring(1);
          }
        }
        if (t.isEmpty) continue;
        span = span.withText(t);
      }
      into.add(span);
    }
  }

  List<CslSpan> _merge(List<CslSpan> spans) {
    final out = <CslSpan>[];
    for (final s in spans) {
      if (s.text.isEmpty) continue;
      if (out.isNotEmpty && out.last.sameStyle(s)) {
        out[out.length - 1] = out.last.withText(out.last.text + s.text);
      } else {
        out.add(s);
      }
    }
    return out;
  }
}
