// Turning a PDF's page text into something pleasant to listen to, and
// cutting it into sentences. Pure functions, no platform.

/// One sentence to speak and the 1-based page it came from.
class Sentence {
  const Sentence(this.page, this.text);
  final int page;
  final String text;

  @override
  String toString() => 'p$page: $text';
}

final _pageNumberOnly = RegExp(
  r'^(?:[-–—\s]*(?:page\s+)?\d{1,4}(?:\s*(?:of|/)\s*\d{1,4})?[-–—\s]*|[ivx]{1,4})$',
  caseSensitive: false,
);
final _referencesHeading = RegExp(
  r'^(?:\d{1,2}\.?\s+)?(?:references?|bibliography|literature cited|works cited)\s*:?$',
  caseSensitive: false,
);

/// What a header/footer line looks like with page numbers blanked, so
/// "Journal of X 12 (2020) 45" matches on every page.
String _shape(String line) => line
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _lines(String text) => [
  for (final l in text.split(RegExp(r'\r\n|\r|\n'))) l.trim(),
];

/// Cleans every page of a document at once (repeated headers and footers
/// can only be told from the whole). Returns one string per page, in
/// order: running page numbers and headers/footers dropped, hyphenated
/// line breaks joined, lines joined into running text, and nothing at all
/// from the references section on (the page holding the heading keeps
/// what precedes it).
List<String> cleanPagesForListening(List<String> pages) {
  final lines = [for (final p in pages) _lines(p)];

  // Header/footer candidates: the first and last two non-empty lines.
  final counts = <String, int>{};
  for (final page in lines) {
    final nonEmpty = [
      for (final l in page)
        if (l.isNotEmpty) l,
    ];
    final edge = <String>{
      ...nonEmpty.take(2).map(_shape),
      ...nonEmpty.reversed.take(2).map(_shape),
    };
    for (final s in edge) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
  }
  final needed = pages.length < 2 ? 1 << 30 : (pages.length < 3 ? 2 : 3);
  final repeated = {
    for (final e in counts.entries)
      if (e.value >= needed && e.key.length > 1) e.key,
  };

  // Where the references begin: the last such heading in the document.
  int? refPage;
  int? refLine;
  for (var p = 0; p < lines.length; p++) {
    for (var i = 0; i < lines[p].length; i++) {
      if (_referencesHeading.hasMatch(lines[p][i])) {
        refPage = p;
        refLine = i;
      }
    }
  }

  final out = <String>[];
  for (var p = 0; p < lines.length; p++) {
    if (refPage != null && p > refPage) {
      out.add('');
      continue;
    }
    final kept = <String>[];
    final page = lines[p];
    final nonEmptyIdx = [
      for (var i = 0; i < page.length; i++)
        if (page[i].isNotEmpty) i,
    ];
    final edgeIdx = {...nonEmptyIdx.take(2), ...nonEmptyIdx.reversed.take(2)};
    for (var i = 0; i < page.length; i++) {
      if (p == refPage && i >= refLine!) break;
      final l = page[i];
      if (l.isEmpty) {
        kept.add('');
        continue;
      }
      if (_pageNumberOnly.hasMatch(l) && edgeIdx.contains(i)) continue;
      if (edgeIdx.contains(i) && repeated.contains(_shape(l))) continue;
      kept.add(l);
    }
    out.add(_joinLines(kept));
  }
  return out;
}

bool _endsSentence(String l) => RegExp(r'[.!?:;"”’)\]]$').hasMatch(l);

String _joinLines(List<String> lines) {
  final b = StringBuffer();
  String? prev;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.isEmpty) {
      // A blank line ends a paragraph.
      if (prev != null && !_endsSentence(prev)) b.write('.');
      prev = null;
      continue;
    }
    if (prev == null) {
      b.write(b.isEmpty ? '' : ' ');
      b.write(l);
    } else if (RegExp(r'[A-Za-z]-$').hasMatch(prev) &&
        RegExp(r'^[a-z]').hasMatch(l)) {
      // "exper-" + "iment" -> "experiment"
      final s = b.toString();
      b
        ..clear()
        ..write(s.substring(0, s.length - 1))
        ..write(l);
    } else if (_looksLikeHeading(prev) && RegExp(r'^[A-Z0-9]').hasMatch(l)) {
      b.write('. $l');
    } else {
      b.write(' $l');
    }
    prev = l;
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _looksLikeHeading(String l) =>
    !_endsSentence(l) &&
    !l.endsWith(',') &&
    !l.endsWith('-') &&
    l.split(' ').length <= 8 &&
    RegExp(r'^[A-Z0-9]').hasMatch(l) &&
    // "of", "and" and friends at the end mean the line runs on.
    !RegExp(
      r'\b(?:of|and|or|the|a|an|to|in|for|with|by|on|at|from|that|which)$',
      caseSensitive: false,
    ).hasMatch(l);

const _abbreviations = {
  'al',
  'fig',
  'figs',
  'eq',
  'eqs',
  'dr',
  'mr',
  'mrs',
  'ms',
  'prof',
  'vs',
  'cf',
  'no',
  'nos',
  'ref',
  'refs',
  'sec',
  'tab',
  'approx',
  'etc',
  'vol',
  'pp',
  'p',
  'st',
  'jr',
  'sr',
  'inc',
  'ltd',
  'co',
  'ca',
  'resp',
  'ed',
  'eds',
  'eg',
  'ie',
  'e.g',
  'i.e',
  'u.s',
  'a.m',
  'p.m',
  'cap',
  'chap',
  'ch',
  'min',
  'max',
  'est',
  'dept',
  'univ',
  'proc',
  'conf',
  'trans',
  'suppl',
  'app',
};

/// Splits [text] into sentences, not fooled by "et al.", "Fig. 2", initials
/// ("J. Smith") or decimals. Over-long sentences are cut at a comma or
/// semicolon so pausing and skipping stay precise.
List<String> splitSentences(String text, {int maxLength = 360}) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return const [];
  final out = <String>[];
  var start = 0;
  final end = RegExp(r'[.!?]+["”’)\]]*\s+(?=["“‘(\[]?[A-Z0-9])');
  for (final m in end.allMatches(t)) {
    final before = t.substring(start, m.start + 1);
    final token = RegExp(r'([\w.]+)\.$')
        .firstMatch(t.substring(0, m.start + 1));
    if (t[m.start] == '.' && m.group(0)!.startsWith('.') && token != null) {
      final word = token.group(1)!.toLowerCase();
      final isInitial = RegExp(r'^[a-z]$', caseSensitive: false).hasMatch(word);
      if (_abbreviations.contains(word) ||
          _abbreviations.contains(word.split('.').last) ||
          isInitial) {
        continue;
      }
    }
    if (before.trim().isEmpty) continue;
    out.add(before.trim());
    start = m.end;
  }
  if (start < t.length) out.add(t.substring(start).trim());
  return [for (final s in out) ..._chop(s, maxLength)];
}

Iterable<String> _chop(String s, int max) sync* {
  var rest = s;
  while (rest.length > max) {
    var cut = rest.lastIndexOf(RegExp(r'[,;] '), max);
    if (cut < max ~/ 3) cut = rest.lastIndexOf(' ', max);
    if (cut <= 0) cut = max;
    yield rest.substring(0, cut + 1).trim();
    rest = rest.substring(cut + 1).trim();
  }
  if (rest.isNotEmpty) yield rest;
}

/// Every sentence of the document in order, tagged with its page.
List<Sentence> sentencesOf(List<String> cleanedPages) => [
  for (var i = 0; i < cleanedPages.length; i++)
    for (final s in splitSentences(cleanedPages[i])) Sentence(i + 1, s),
];

/// A rough language guess from common words: a BCP-47 code, or null when
/// unsure (then the system language is used).
String? guessLanguage(String text) {
  const stop = {
    'en': ['the', 'and', 'of', 'to', 'in', 'is', 'that', 'for', 'with', 'are'],
    'de': [
      'der',
      'die',
      'und',
      'das',
      'ist',
      'nicht',
      'mit',
      'ein',
      'von',
      'zu',
    ],
    'fr': ['le', 'la', 'les', 'des', 'et', 'est', 'que', 'dans', 'pour', 'une'],
    'es': ['el', 'los', 'las', 'del', 'que', 'y', 'es', 'una', 'por', 'con'],
  };
  final words = RegExp(r'[a-zäöüßéèàçñ]+')
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .take(3000)
      .toList();
  if (words.length < 40) return null;
  String? best;
  var bestScore = 0;
  var second = 0;
  stop.forEach((lang, list) {
    final set = list.toSet();
    final score = words.where(set.contains).length;
    if (score > bestScore) {
      second = bestScore;
      bestScore = score;
      best = lang;
    } else if (score > second) {
      second = score;
    }
  });
  return bestScore >= words.length * 0.08 && bestScore > second * 1.3
      ? best
      : null;
}
