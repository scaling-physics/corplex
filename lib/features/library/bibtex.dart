import '../../data/database.dart';
import 'authors.dart';
import 'citation_formatter.dart';

/// A paper as described by a `.bib` entry (or any other source), before it
/// becomes a row. Only what the Library stores.
class PaperMetadata {
  const PaperMetadata({
    required this.title,
    this.authors = '',
    this.year,
    this.venue,
    this.doi,
    this.pmid,
    this.url,
    this.abstract,
  });

  final String title;

  /// In the canonical stored form (see [authorsToStored]).
  final String authors;
  final int? year;
  final String? venue;
  final String? doi;

  /// PubMed id (digits), a link to the paper's page, and its abstract as
  /// plain text — each optional and only ever filled into an empty field.
  final String? pmid;
  final String? url;
  final String? abstract;

  /// This record, with anything it lacks taken from [other].
  PaperMetadata withFallback(PaperMetadata? other) {
    if (other == null) return this;
    String? pick(String? a, String? b) => (a ?? '').trim().isEmpty ? b : a;
    return PaperMetadata(
      title: title,
      authors: authors.isEmpty ? other.authors : authors,
      year: year ?? other.year,
      venue: pick(venue, other.venue),
      doi: pick(doi, other.doi),
      pmid: pick(pmid, other.pmid),
      url: pick(url, other.url),
      abstract: pick(abstract, other.abstract),
    );
  }
}

/// Parses a BibTeX file into [PaperMetadata], one per entry that has a
/// title. Understands `{…}` and `"…"` values (with nested braces), bare
/// numbers, `@string` abbreviations (used by name), and common LaTeX
/// accents. `@comment`/`@preamble` are skipped. Malformed entries are
/// skipped rather than failing the whole file.
List<PaperMetadata> parseBibtex(String source) {
  final strings = <String, String>{
    'jan': 'January',
    'feb': 'February',
    'mar': 'March',
    'apr': 'April',
    'may': 'May',
    'jun': 'June',
    'jul': 'July',
    'aug': 'August',
    'sep': 'September',
    'oct': 'October',
    'nov': 'November',
    'dec': 'December',
  };
  final results = <PaperMetadata>[];
  var i = 0;

  while (true) {
    i = source.indexOf('@', i);
    if (i < 0) break;
    final head = RegExp(r'@\s*(\w+)\s*([{(])').matchAsPrefix(source, i);
    if (head == null) {
      i++;
      continue;
    }
    final type = head.group(1)!.toLowerCase();
    final open = head.group(2)!;
    final close = open == '{' ? '}' : ')';
    final bodyStart = head.end;
    final bodyEnd = _matchingClose(source, bodyStart - 1, open, close);
    if (bodyEnd < 0) break; // truncated file
    final body = source.substring(bodyStart, bodyEnd);
    i = bodyEnd + 1;

    if (type == 'comment' || type == 'preamble') continue;
    if (type == 'string') {
      strings.addAll(_fields(body, strings));
      continue;
    }
    // Skip the citation key (everything up to the first comma).
    final firstComma = body.indexOf(',');
    if (firstComma < 0) continue;
    final fields = _fields(body.substring(firstComma + 1), strings);
    final title = _clean(fields['title'] ?? '');
    if (title.isEmpty) continue;

    final authorRaw = _clean(fields['author'] ?? fields['editor'] ?? '');
    results.add(
      PaperMetadata(
        title: title,
        authors: authorRaw.isEmpty
            ? ''
            : authorsToStored(parseAuthors(authorRaw)),
        year: int.tryParse(
          RegExp(r'\d{4}').firstMatch(fields['year'] ?? '')?.group(0) ?? '',
        ),
        venue: _nonEmpty(
          _clean(
            fields['journal'] ??
                fields['booktitle'] ??
                fields['publisher'] ??
                fields['howpublished'] ??
                '',
          ),
        ),
        doi: _nonEmpty(_normalizeDoi(fields['doi'] ?? fields['url'] ?? '')),
        pmid: _pmidFromBibtex(fields),
        url: _urlFromBibtex(fields),
        abstract: _nonEmpty(_cleanParagraphs(fields['abstract'] ?? '')),
      ),
    );
  }
  return results;
}

/// `pmid = {123}`, or the PubMed id of `eprint` when `archiveprefix`/
/// `eprinttype` says pubmed.
String? _pmidFromBibtex(Map<String, String> f) {
  final direct = RegExp(r'\d{1,9}')
      .firstMatch(_clean(f['pmid'] ?? ''))
      ?.group(0);
  if (direct != null) return direct;
  final kind = (f['archiveprefix'] ?? f['eprinttype'] ?? '').toLowerCase();
  if (kind == 'pubmed') {
    return RegExp(r'\d{1,9}').firstMatch(_clean(f['eprint'] ?? ''))?.group(0);
  }
  return null;
}

/// The `url` field, unless it is only a doi.org link (the DOI says that).
String? _urlFromBibtex(Map<String, String> f) {
  final raw = _clean(f['url'] ?? '').replaceAll(RegExp(r'\s'), '');
  if (raw.isEmpty) return null;
  if (RegExp(
    r'^https?://(dx\.)?doi\.org/',
    caseSensitive: false,
  ).hasMatch(raw)) {
    return null;
  }
  return raw;
}

/// Like [_clean] but keeps blank-line paragraph breaks.
String _cleanParagraphs(String value) => value
    .split(RegExp(r'\n\s*\n'))
    .map(_clean)
    .where((p) => p.isNotEmpty)
    .join('\n\n');

String? _nonEmpty(String s) => s.isEmpty ? null : s;

/// Index of the delimiter closing the one at [open], respecting nesting.
int _matchingClose(String s, int open, String openCh, String closeCh) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == '\\') {
      i++; // escaped character
    } else if (c == openCh) {
      depth++;
    } else if (c == closeCh) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\r' || c == '\n';

/// `name = value` pairs of an entry body; values resolved to plain text.
Map<String, String> _fields(String body, Map<String, String> strings) {
  final fields = <String, String>{};
  var i = 0;
  while (i < body.length) {
    final name = RegExp(r'\s*,?\s*([\w\-:.]+)\s*=\s*').matchAsPrefix(body, i);
    if (name == null) {
      i++;
      continue;
    }
    i = name.end;
    final value = StringBuffer();
    // A value is one or more pieces joined by '#'.
    while (i < body.length) {
      while (i < body.length && _isSpace(body[i])) {
        i++;
      }
      if (i >= body.length) break;
      final c = body[i];
      if (c == '{') {
        final end = _matchingClose(body, i, '{', '}');
        if (end < 0) {
          value.write(body.substring(i + 1));
          i = body.length;
        } else {
          value.write(body.substring(i + 1, end));
          i = end + 1;
        }
      } else if (c == '"') {
        var j = i + 1;
        var depth = 0;
        while (j < body.length && !(body[j] == '"' && depth == 0)) {
          if (body[j] == '\\') {
            j++;
          } else if (body[j] == '{') {
            depth++;
          } else if (body[j] == '}') {
            depth--;
          }
          j++;
        }
        final end = j.clamp(0, body.length);
        value.write(body.substring(i + 1, end));
        i = end + 1;
      } else {
        final bare = RegExp(r'[\w\-:.]+').matchAsPrefix(body, i);
        if (bare == null) break;
        final word = bare.group(0)!;
        value.write(strings[word.toLowerCase()] ?? word);
        i = bare.end;
      }
      while (i < body.length && _isSpace(body[i])) {
        i++;
      }
      if (i < body.length && body[i] == '#') {
        i++;
        continue;
      }
      break;
    }
    fields[name.group(1)!.toLowerCase()] = value.toString();
  }
  return fields;
}

const _accents = {
  '"a': 'ä',
  '"o': 'ö',
  '"u': 'ü',
  '"A': 'Ä',
  '"O': 'Ö',
  '"U': 'Ü',
  "'a": 'á',
  "'e": 'é',
  "'i": 'í',
  "'o": 'ó',
  "'u": 'ú',
  "'E": 'É',
  '`a': 'à',
  '`e': 'è',
  '`o': 'ò',
  '^e': 'ê',
  '^o': 'ô',
  '^a': 'â',
  '~n': 'ñ',
  '~a': 'ã',
  '~o': 'õ',
  'cc': 'ç',
  'vs': 'š',
  'vc': 'č',
  'vz': 'ž',
};

/// Plain text from a BibTeX value: braces and common LaTeX escapes gone.
String _clean(String value) {
  var s = value;
  // \"{u}  \"u  {\"u}  \'\i
  s = s.replaceAllMapped(
    RegExp(r'''\\(["'`^~])\s*\{?\\?(\w)\}?'''),
    (m) => _accents['${m[1]}${m[2]}'] ?? (m[2] == 'i' ? 'í' : m[2]!),
  );
  s = s.replaceAllMapped(
    RegExp(r'\\([cv])\s*\{?(\w)\}?'),
    (m) => _accents['${m[1]}${m[2]}'] ?? m[2]!,
  );
  s = s
      .replaceAll(r'\&', '&')
      .replaceAll(r'\%', '%')
      .replaceAll(r'\_', '_')
      .replaceAll(r'\ss', 'ß')
      .replaceAll('--', '–')
      .replaceAll(RegExp(r'\\[a-zA-Z]+\s*'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

/// A DOI from a `doi` field or a `https://doi.org/…` URL.
String _normalizeDoi(String raw) =>
    RegExp(r'10\.\d{4,9}/[^\s"<>{}]+').firstMatch(raw)?.group(0) ?? '';

/// One BibTeX entry per paper, separated by blank lines — what the
/// Library's "Export BibTeX" shares. Keys are made unique within the file.
String exportBibtex(Iterable<Paper> papers) {
  final used = <String>{};
  final entries = <String>[];
  for (final paper in papers) {
    var entry = formatCitation(paper, CitationStyle.bibtex);
    final key = bibtexKey(paper);
    var unique = key;
    for (var n = 2; !used.add(unique); n++) {
      unique = '$key${String.fromCharCode(96 + n)}'; // …b, …c
    }
    if (unique != key) entry = entry.replaceFirst('{$key,', '{$unique,');
    entries.add(entry);
  }
  return '${entries.join('\n\n')}\n';
}
