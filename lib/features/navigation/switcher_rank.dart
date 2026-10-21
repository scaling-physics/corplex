import '../notes/note_sections.dart' show NoteHeading;
import 'nav_target.dart';

/// What a quick-switcher row stands for.
enum SwitcherKind { note, paper, project, savedSearch, folder, tag }

/// One thing the quick switcher can go to. Pure data, so ranking is
/// testable without a database.
class SwitcherItem {
  const SwitcherItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.keywords = const [],
    this.updatedAt,
    this.pinned = false,
    this.locked = false,
    this.query,
    this.pdfPage,
    this.hasPdf = false,
  });

  final SwitcherKind kind;
  final String id;
  final String title;

  /// Quiet second line (folder, "venue year", "Project").
  final String subtitle;

  /// Other names that also match: note aliases, a paper's authors and
  /// citekey. They rank below a title match of the same quality.
  final List<String> keywords;
  final DateTime? updatedAt;
  final bool pinned;
  final bool locked;

  /// A saved search's query text.
  final String? query;

  /// A paper's last-read page, and whether its PDF is on this device.
  final int? pdfPage;
  final bool hasPdf;

  /// The history key of this item, if it is a place ([NavTarget.key]).
  String? get targetKey => switch (kind) {
    SwitcherKind.note => 'note:$id',
    SwitcherKind.paper => 'paper:$id',
    SwitcherKind.project => 'project:$id',
    _ => null,
  };

  NavTarget? get target => switch (kind) {
    SwitcherKind.note => NoteTarget(id),
    SwitcherKind.paper => PaperTarget(id),
    SwitcherKind.project => ProjectTarget(id),
    _ => null,
  };
}

/// Lowercase, accents folded (the common Latin ones), so "Müller" is found
/// by "muller" and "Café" by "cafe".
String foldForMatch(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    out.write(_folds[c] ?? c);
  }
  return out.toString();
}

const _folds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u',
  'ý': 'y', 'ÿ': 'y',
  'š': 's', 'ś': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z', 'ł': 'l', 'ř': 'r',
  'ß': 's',
};

/// How well [query] matches [text] (both already folded): 0 exact, 1 prefix,
/// 2 a word starts with it, 3 it occurs inside, 4 every word of the query
/// occurs, 5 its letters appear in order. Null when none of these.
int? matchTier(String query, String text) {
  if (query.isEmpty || text.isEmpty) return null;
  if (text == query) return 0;
  if (text.startsWith(query)) return 1;
  final at = text.indexOf(query);
  if (at > 0 && _isBoundary(text, at)) return 2;
  var from = 0;
  while (true) {
    final i = text.indexOf(query, from);
    if (i < 0) break;
    if (i == 0 || _isBoundary(text, i)) return 2;
    from = i + 1;
  }
  if (at >= 0) return 3;
  final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.length > 1 && words.every(text.contains)) return 4;
  return _isSubsequence(query.replaceAll(' ', ''), text) ? 5 : null;
}

bool _isBoundary(String text, int i) {
  final prev = text.codeUnitAt(i - 1);
  final isWord =
      (prev >= 0x30 && prev <= 0x39) ||
      (prev >= 0x61 && prev <= 0x7a) ||
      prev > 0x7f;
  return !isWord;
}

bool _isSubsequence(String needle, String hay) {
  if (needle.isEmpty) return false;
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
  }
  return i == needle.length;
}

/// The items matching [query], best first, at most [limit]. Order: match
/// quality (exact > prefix > word-prefix > inside > all words > letters in
/// order; a title beats an alias/author/citekey of the same quality), then
/// pinned, then most recently updated, then title. An empty query keeps the
/// items' own order.
List<SwitcherItem> rankSwitcherItems(
  List<SwitcherItem> items,
  String query, {
  int limit = 40,
}) {
  final q = foldForMatch(query.trim());
  if (q.isEmpty) return items.take(limit).toList();
  final scored = <(SwitcherItem, int)>[];
  for (final item in items) {
    final title = matchTier(q, foldForMatch(item.title));
    var best = title == null ? null : title * 2;
    for (final k in item.keywords) {
      final t = matchTier(q, foldForMatch(k));
      if (t == null) continue;
      final score = t * 2 + 1;
      if (best == null || score < best) best = score;
    }
    if (best != null) scored.add((item, best));
  }
  scored.sort((a, b) {
    final byScore = a.$2.compareTo(b.$2);
    if (byScore != 0) return byScore;
    if (a.$1.pinned != b.$1.pinned) return a.$1.pinned ? -1 : 1;
    final at = a.$1.updatedAt, bt = b.$1.updatedAt;
    if (at != null && bt != null) {
      final byTime = bt.compareTo(at);
      if (byTime != 0) return byTime;
    } else if (at != null || bt != null) {
      return at != null ? -1 : 1;
    }
    return foldForMatch(a.$1.title).compareTo(foldForMatch(b.$1.title));
  });
  return [for (final (item, _) in scored.take(limit)) item];
}

/// The headings of a note matching [query] (same ranking, by quality then
/// document order), as indexes into [headings].
List<int> rankHeadings(List<NoteHeading> headings, String query) {
  final q = foldForMatch(query.trim());
  if (q.isEmpty) return [for (var i = 0; i < headings.length; i++) i];
  final scored = <(int, int)>[];
  for (var i = 0; i < headings.length; i++) {
    final t = matchTier(q, foldForMatch(headings[i].text));
    if (t != null) scored.add((i, t));
  }
  scored.sort((a, b) {
    final byTier = a.$2.compareTo(b.$2);
    return byTier != 0 ? byTier : a.$1.compareTo(b.$1);
  });
  return [for (final (i, _) in scored) i];
}

/// The recents shown for an empty query: history entries newest first,
/// without repeats, without the place already open ([currentKey]), and only
/// those still in [byKey] (deleted ones are gone), up to [limit]; then the
/// pinned notes in [pinned] that aren't among them.
({List<SwitcherItem> recent, List<SwitcherItem> pinned}) switcherRecents({
  required List<String> historyNewestFirst,
  required Map<String, SwitcherItem> byKey,
  required List<SwitcherItem> pinned,
  String? currentKey,
  int limit = 8,
}) {
  final seen = <String>{?currentKey};
  final recent = <SwitcherItem>[];
  for (final key in historyNewestFirst) {
    if (recent.length >= limit) break;
    if (!seen.add(key)) continue;
    final item = byKey[key];
    if (item != null) recent.add(item);
  }
  final pins = [
    for (final p in pinned)
      if (p.targetKey != currentKey && !recent.any((r) => r.id == p.id)) p,
  ];
  return (recent: recent, pinned: pins);
}

/// The first heading starting after [caret] (forward) or the last starting
/// before it (back), in [headings]' document order; null when there is none.
NoteHeading? adjacentHeading(
  List<NoteHeading> headings,
  int caret, {
  required bool forward,
}) {
  if (forward) {
    for (final h in headings) {
      if (h.offset > caret) return h;
    }
    return null;
  }
  for (final h in headings.reversed) {
    if (h.offset < caret) return h;
  }
  return null;
}
