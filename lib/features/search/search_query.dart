/// Parsing of the search box's text into words, phrases and filters.
///
/// Pure and total: any string parses, and the FTS5 `MATCH` string
/// ([SearchQuery.ftsMatch]) is built only from the words and phrases found
/// here, each quoted, so a stray quote, `-`, `NOT`, `*`, `^` or parenthesis
/// can never become FTS syntax (or an error).
///
/// Syntax: plain words (all must match, each as a prefix), `"exact phrase"`,
/// `-word`, `tag:x`, `folder:x` (alias `path:`), `project:x`, `in:notes`
/// (`papers`, `highlights`, `pdfs`), `is:pinned` (`template`, `daily`), and
/// `-` in front of any of them to exclude. A value with spaces is quoted
/// (`tag:"deep learning"`). Operator names are case-insensitive; an unknown
/// `foo:bar`, or a known operator with an unknown value, is just words.
library;

import 'search_index.dart' show SearchKind;

enum SearchField { tag, folder, project, isPinned, isTemplate, isDaily }

/// One `tag:x` / `-is:pinned` style condition. [value] is lower-case (empty
/// for the `is:` fields).
class SearchFilter {
  const SearchFilter(this.field, this.value, {this.negated = false});

  final SearchField field;
  final String value;
  final bool negated;

  /// Only notes can satisfy it (papers and highlights have no tags, folders
  /// or pin state).
  bool get notesOnly => field != SearchField.project;

  @override
  String toString() => '${negated ? '-' : ''}${field.name}:$value';

  @override
  bool operator ==(Object other) =>
      other is SearchFilter &&
      other.field == field &&
      other.value == value &&
      other.negated == negated;

  @override
  int get hashCode => Object.hash(field, value, negated);
}

/// A word (matched as a prefix) or, with several [words], an exact phrase.
class SearchTerm {
  const SearchTerm(this.words, {this.phrase = false, this.negated = false});

  final List<String> words;
  final bool phrase;
  final bool negated;

  /// FTS5 text for this term: every token is quoted.
  String get fts =>
      phrase ? '"${words.join(' ')}"' : words.map((w) => '"$w"*').join(' ');

  @override
  String toString() =>
      '${negated ? '-' : ''}${phrase ? '"' : ''}'
      '${words.join(' ')}${phrase ? '"' : ''}';

  @override
  bool operator ==(Object other) =>
      other is SearchTerm &&
      other.phrase == phrase &&
      other.negated == negated &&
      other.words.join(' ') == words.join(' ');

  @override
  int get hashCode => Object.hash(words.join(' '), phrase, negated);
}

class SearchQuery {
  const SearchQuery({
    this.terms = const [],
    this.filters = const [],
    this.kinds = const {},
    this.excludedKinds = const {},
  });

  final List<SearchTerm> terms;
  final List<SearchFilter> filters;

  /// `in:` — when non-empty, only these kinds are searched.
  final Set<SearchKind> kinds;

  /// `-in:` — these kinds are left out.
  final Set<SearchKind> excludedKinds;

  Iterable<SearchTerm> get positive => terms.where((t) => !t.negated);
  Iterable<SearchTerm> get negative => terms.where((t) => t.negated);

  /// Nothing to search for at all (blank, or only punctuation).
  bool get isEmpty =>
      terms.isEmpty &&
      filters.isEmpty &&
      kinds.isEmpty &&
      excludedKinds.isEmpty;

  bool get hasPositiveTerms => positive.isNotEmpty;

  bool allowsKind(SearchKind kind) =>
      (kinds.isEmpty || kinds.contains(kind)) && !excludedKinds.contains(kind);

  /// The `MATCH` string, or null when there is no positive term to look up
  /// (negative-only and filter-only queries scan instead).
  String? get ftsMatch {
    final pos = positive.toList();
    if (pos.isEmpty) return null;
    final buffer = StringBuffer(pos.map((t) => t.fts).join(' '));
    final neg = negative.toList();
    if (neg.isNotEmpty) {
      // NOT binds tighter than the implicit AND, hence the parentheses.
      return '(${buffer.toString()}) NOT '
          '(${neg.map((t) => neg.length == 1 ? t.fts : '(${t.fts})').join(' OR ')})';
    }
    return buffer.toString();
  }

  /// The positive words and phrases as plain text, for in-document Find.
  String get plainText => positive.map((t) => t.words.join(' ')).join(' ');

  /// Whether [title] + [body] satisfy every term. Used where FTS can't
  /// answer (negative-only queries, and when FTS5 isn't compiled in).
  bool matchesText(String title, String body) {
    final text = ' ${_normalize('$title $body')} ';
    for (final t in terms) {
      final bool found;
      if (t.phrase) {
        found = text.contains(' ${t.words.join(' ')} ');
      } else {
        found = t.words.every(text.contains);
      }
      if (found == t.negated) return false;
    }
    return true;
  }

  @override
  String toString() => [
    ...terms.map((t) => '$t'),
    ...filters.map((f) => '$f'),
    if (kinds.isNotEmpty) 'in:${kinds.map((k) => k.name).join(',')}',
  ].join(' ');
}

String _normalize(String s) =>
    _wordPattern.allMatches(s.toLowerCase()).map((m) => m.group(0)!).join(' ');

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<String> _wordsOf(String s) =>
    _wordPattern.allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

SearchKind? _kindFor(String v) => switch (v) {
  'notes' || 'note' => SearchKind.note,
  'papers' || 'paper' => SearchKind.paper,
  'highlights' || 'highlight' => SearchKind.highlight,
  'pdfs' || 'pdf' => SearchKind.pdfText,
  _ => null,
};

SearchField? _isFieldFor(String v) => switch (v) {
  'pinned' => SearchField.isPinned,
  'template' || 'templates' => SearchField.isTemplate,
  'daily' => SearchField.isDaily,
  _ => null,
};

/// Parses [input]; see the library comment for the syntax.
SearchQuery parseSearchQuery(String input) {
  final terms = <SearchTerm>[];
  final filters = <SearchFilter>[];
  final kinds = <SearchKind>{};
  final excluded = <SearchKind>{};

  void word(String text, {required bool negated}) {
    for (final w in _wordsOf(text)) {
      terms.add(SearchTerm([w], negated: negated));
    }
  }

  void phrase(String text, {required bool negated}) {
    final words = _wordsOf(text);
    if (words.isEmpty) return;
    terms.add(SearchTerm(words, phrase: true, negated: negated));
  }

  var i = 0;
  final n = input.length;
  bool isSpace(String c) => c.trim().isEmpty;

  // Reads a quoted run starting at the opening quote at [start]; an
  // unbalanced quote runs to the end. Returns the text and the next index.
  (String, int) quoted(int start) {
    final close = input.indexOf('"', start + 1);
    if (close < 0) return (input.substring(start + 1), n);
    return (input.substring(start + 1, close), close + 1);
  }

  while (i < n) {
    if (isSpace(input[i])) {
      i++;
      continue;
    }
    var negated = false;
    if (input[i] == '-') {
      negated = true;
      i++;
      // A lone "-" (or "- word") excludes nothing.
      if (i >= n || isSpace(input[i])) continue;
    }
    if (input[i] == '"') {
      final (text, next) = quoted(i);
      phrase(text, negated: negated);
      i = next;
      continue;
    }
    // A chunk up to the next space or quote.
    var j = i;
    while (j < n && !isSpace(input[j]) && input[j] != '"') {
      j++;
    }
    final chunk = input.substring(i, j);
    final colon = chunk.indexOf(':');
    final name = colon > 0 ? chunk.substring(0, colon).toLowerCase() : '';
    const operators = {'tag', 'folder', 'path', 'project', 'in', 'is'};
    if (operators.contains(name)) {
      String value;
      var next = j;
      if (colon == chunk.length - 1 && j < n && input[j] == '"') {
        final (text, after) = quoted(j);
        value = text;
        next = after;
      } else {
        value = chunk.substring(colon + 1);
      }
      if (_applyOperator(name, value, negated, filters, kinds, excluded)) {
        i = next;
        continue;
      }
      if (value.trim().isEmpty && colon == chunk.length - 1) {
        // "tag:" with nothing after it: ignore the operator.
        i = next;
        continue;
      }
    }
    word(chunk, negated: negated);
    i = j;
  }
  return SearchQuery(
    terms: terms,
    filters: filters,
    kinds: kinds,
    excludedKinds: excluded,
  );
}

bool _applyOperator(
  String name,
  String raw,
  bool negated,
  List<SearchFilter> filters,
  Set<SearchKind> kinds,
  Set<SearchKind> excluded,
) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return false;
  switch (name) {
    case 'tag':
      final tag = value.startsWith('#') ? value.substring(1).trim() : value;
      if (tag.isEmpty) return false;
      filters.add(SearchFilter(SearchField.tag, tag, negated: negated));
    case 'folder' || 'path':
      filters.add(SearchFilter(SearchField.folder, value, negated: negated));
    case 'project':
      filters.add(SearchFilter(SearchField.project, value, negated: negated));
    case 'in':
      final kind = _kindFor(value);
      if (kind == null) return false;
      (negated ? excluded : kinds).add(kind);
    case 'is':
      final field = _isFieldFor(value);
      if (field == null) return false;
      filters.add(SearchFilter(field, '', negated: negated));
    default:
      return false;
  }
  return true;
}
