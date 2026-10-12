import '../../data/database.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import 'csl_item.dart';
import 'csl_processor.dart';
import 'csl_rich.dart';

/// Reference entries for [papers] in [style], with their text styling.
/// [papers] are in citation order (numbered styles number them that way);
/// the result is in the style's own order (alphabetical, or citation
/// order). Loads the style first. Falls back to the hand-written formatter
/// for BibTeX or a style that can't be loaded.
Future<List<CslRich>> referenceEntries(
  List<Paper> papers,
  CitationStyle style,
) async {
  if (papers.isEmpty) return const [];
  final csl = await style.ensureLoaded();
  if (csl != null) {
    try {
      final out = CslProcessor(csl)
          .process([for (final p in papers) paperToCsl(p)]);
      return [
        for (final e in out.bibliography)
          if (!e.isEmpty) e,
      ];
    } catch (_) {
      // Fall back below.
    }
  }
  return [
    for (final line in referenceList(papers, style)) CslRich([CslSpan(line)]),
  ];
}

/// [referenceEntries] as plain strings.
Future<List<String>> referenceLines(
  List<Paper> papers,
  CitationStyle style,
) async => [for (final e in await referenceEntries(papers, style)) e.plain];

/// In-text citations for one document in a CSL style. Build it with the
/// text of the whole document in order, then call [replace] on the same
/// pieces in the same order.
class CslCitationPlan {
  CslCitationPlan._(this._texts, this._papers, this._order);

  final List<CslRich> _texts;
  final List<Paper> _papers;
  final List<int> _order;
  var _next = 0;

  /// The papers cited, in order of first citation.
  List<Paper> get cited => _papers;

  static final _marker = RegExp(r'\[@[^\]]+\]');

  /// Reads every `[@key]` marker in [pieces] (in order) and formats them.
  /// Returns null when [style] isn't a CSL style that can be loaded.
  static Future<CslCitationPlan?> build(
    Iterable<String> pieces,
    Map<String, Paper> byKey,
    CitationStyle style,
  ) async {
    final csl = await style.ensureLoaded();
    if (csl == null) return null;
    final keyIndex = <String, int>{};
    final papers = <Paper>[];
    final clusters = <List<int>>[];
    final order = <int>[]; // marker occurrence -> cluster index or -1
    for (final text in pieces) {
      for (final m in _marker.allMatches(text)) {
        final keys = citedKeys(m.group(0)!);
        if (keys.isEmpty || keys.any((k) => !byKey.containsKey(k))) {
          order.add(-1);
          continue;
        }
        final cluster = <int>[];
        for (final k in keys) {
          cluster.add(
            keyIndex.putIfAbsent(k, () {
              papers.add(byKey[k]!);
              return papers.length - 1;
            }),
          );
        }
        order.add(clusters.length);
        clusters.add(cluster);
      }
    }
    if (papers.isEmpty) return CslCitationPlan._(const [], const [], order);
    final out = CslProcessor(csl)
        .process([for (final p in papers) paperToCsl(p)], clusters: clusters);
    return CslCitationPlan._(out.citations, papers, order);
  }

  /// [text] with its markers replaced; call in the order given to [build].
  String replace(String text) => text.replaceAllMapped(_marker, (m) {
    final c = _order[_next++];
    return c < 0 ? m.group(0)! : _texts[c].plainWithSuperscripts;
  });
}
