import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/database.dart';
import 'authors.dart';
import 'bibtex.dart';

/// What kind of identifier a string is, and its normalized form.
enum IdentifierKind { doi, arxiv }

class PaperIdentifier {
  const PaperIdentifier(this.kind, this.value);

  final IdentifierKind kind;

  /// Bare DOI (`10.1000/xyz`) or arXiv id (`1706.03762`, `cs/0112017`).
  final String value;

  @override
  bool operator ==(Object other) =>
      other is PaperIdentifier && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '${kind.name}:$value';
}

final _doiPattern = RegExp(r'10\.\d{4,9}/[^\s"<>{}\[\]]+');
final _arxivPattern = RegExp(
  r'(?:arxiv[:\s/]*|arxiv\.org/(?:abs|pdf)/)((?:\d{4}\.\d{4,5}|[a-z\-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?)',
  caseSensitive: false,
);
final _bareArxiv = RegExp(r'^\d{4}\.\d{4,5}(?:v\d+)?$');

/// Recognizes a DOI, a `doi.org` link, `arXiv:1706.03762`, an arxiv.org
/// link, or a bare arXiv id in [input]. Trailing punctuation from prose
/// ("…xyz).") is trimmed.
PaperIdentifier? parseIdentifier(String input) {
  final text = input.trim();
  final arxiv = _arxivPattern.firstMatch(text)?.group(1);
  if (arxiv != null && !_doiPattern.hasMatch(text)) {
    return PaperIdentifier(IdentifierKind.arxiv, _stripVersion(arxiv));
  }
  final doi = _doiPattern.firstMatch(text)?.group(0);
  if (doi != null) {
    return PaperIdentifier(IdentifierKind.doi, _trimDoi(doi));
  }
  if (_bareArxiv.hasMatch(text)) {
    return PaperIdentifier(IdentifierKind.arxiv, _stripVersion(text));
  }
  return null;
}

String _stripVersion(String id) => id.replaceFirst(RegExp(r'v\d+$'), '');

String _trimDoi(String doi) => doi.replaceFirst(RegExp(r'[.,;:)\]]+$'), '');

/// Looks for a DOI or arXiv id printed in a PDF's text — first page or two
/// of a paper carries it in the header, footer, or arXiv stamp.
PaperIdentifier? findIdentifierInText(String text) {
  final doi = RegExp(
    r'(?:doi[:\s]*|doi\.org/)(10\.\d{4,9}/[^\s"<>{}\[\]]+)',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  if (doi != null) return PaperIdentifier(IdentifierKind.doi, _trimDoi(doi));
  final arxiv = RegExp(
    r'arXiv:\s*((?:\d{4}\.\d{4,5}|[a-z\-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?)',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  if (arxiv != null) {
    return PaperIdentifier(IdentifierKind.arxiv, _stripVersion(arxiv));
  }
  final bare = _doiPattern.firstMatch(text)?.group(0);
  return bare == null
      ? null
      : PaperIdentifier(IdentifierKind.doi, _trimDoi(bare));
}

/// Fetches bibliographic details for an identifier. Online only, and
/// always optional: failures return null / throw [LookupFailed], and the
/// paper can be filled in by hand.
class MetadataLookup {
  MetadataLookup({http.Client? client, this.contactEmail})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Crossref asks polite clients to identify themselves; optional.
  final String? contactEmail;

  static const _timeout = Duration(seconds: 12);

  Future<PaperMetadata?> lookup(PaperIdentifier id) => switch (id.kind) {
    IdentifierKind.doi => crossref(id.value),
    IdentifierKind.arxiv => arxiv(id.value),
  };

  Future<PaperMetadata?> crossref(String doi) async {
    final uri = Uri.https(
      'api.crossref.org',
      '/works/${Uri.encodeComponent(doi).replaceAll('%2F', '/')}',
      {?(contactEmail == null ? null : 'mailto'): contactEmail},
    );
    final response = await _get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw const LookupFailed();
    try {
      return parseCrossref(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      throw const LookupFailed();
    }
  }

  Future<PaperMetadata?> arxiv(String id) async {
    final response = await _get(
      Uri.http('export.arxiv.org', '/api/query', {'id_list': id}),
    );
    if (response.statusCode != 200) throw const LookupFailed();
    return parseArxiv(response.body, id);
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } catch (_) {
      throw const LookupFailed();
    }
  }
}

/// The lookup couldn't be completed (offline, timeout, server trouble) —
/// as opposed to "no such paper", which is a null result.
class LookupFailed implements Exception {
  const LookupFailed();

  @override
  String toString() => 'Couldn\'t reach the lookup service.';
}

PaperMetadata? parseCrossref(Map<String, dynamic> json) {
  final message = json['message'] as Map<String, dynamic>?;
  if (message == null) return null;
  final title = _first(message['title']);
  if (title == null || title.trim().isEmpty) return null;

  final authors = <Author>[
    for (final a in (message['author'] as List? ?? const []))
      if (a is Map && (a['family'] ?? a['name']) != null)
        Author(
          family: '${a['family'] ?? a['name']}',
          given: '${a['given'] ?? ''}',
        ),
  ];
  final dateParts =
      ((message['issued'] ?? message['published']) as Map?)?['date-parts']
          as List?;
  final year =
      dateParts is List && dateParts.isNotEmpty && dateParts.first is List
      ? ((dateParts.first as List).firstOrNull as num?)?.toInt()
      : null;

  return PaperMetadata(
    title: _stripTags(title),
    authors: authorsToStored(AuthorList(authors)),
    year: year,
    venue:
        _first(message['container-title']) ?? message['publisher'] as String?,
    doi: message['DOI'] as String?,
  );
}

String? _first(Object? value) =>
    value is List && value.isNotEmpty ? '${value.first}' : null;

/// Crossref titles can carry JATS/MathML markup.
String _stripTags(String s) =>
    s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Reads the first `<entry>` of an arXiv Atom feed. arXiv answers an
/// unknown id with an entry that has no title/`<id>` content, so a missing
/// title means "not found".
PaperMetadata? parseArxiv(String atom, String id) {
  final entry = RegExp(
    r'<entry>(.*?)</entry>',
    dotAll: true,
  ).firstMatch(atom)?.group(1);
  if (entry == null) return null;
  String? tag(String name) => RegExp(
    '<$name[^>]*>(.*?)</$name>',
    dotAll: true,
  ).firstMatch(entry)?.group(1)?.trim();

  final title = tag('title')?.replaceAll(RegExp(r'\s+'), ' ');
  if (title == null || title.isEmpty || title.toLowerCase() == 'error') {
    return null;
  }
  final authors = [
    for (final m in RegExp(
      r'<author>\s*<name>(.*?)</name>',
      dotAll: true,
    ).allMatches(entry))
      m.group(1)!.trim(),
  ];
  final published = tag('published');
  return PaperMetadata(
    title: _unescape(title),
    authors: authorsToStored(parseAuthors(authors.map(_unescape).join('; '))),
    year: published == null ? null : int.tryParse(published.substring(0, 4)),
    venue:
        tag('arxiv:journal_ref')?.replaceAll(RegExp(r'\s+'), ' ') ??
        'arXiv:$id',
    // The published version's DOI if arXiv knows it, else the DOI arXiv
    // registers for every preprint — so the paper always has one to cite
    // and the DOI field isn't left empty.
    doi: tag('arxiv:doi') ?? '10.48550/arXiv.$id',
  );
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

final metadataLookupProvider = Provider<MetadataLookup>(
  (ref) => MetadataLookup(),
);

// ---------------------------------------------------------------- duplicates

String _normalizeTitle(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String? _normalizeDoiKey(String? doi) {
  if (doi == null) return null;
  final d = _trimDoi(doi.trim().toLowerCase())
      .replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/'), '');
  return d.isEmpty ? null : d;
}

/// Is [candidate] already in the library? Same DOI, or the same title
/// (ignoring case/punctuation) with a compatible year.
Future<Paper?> findDuplicate(
  AppDatabase db,
  PaperMetadata candidate, {
  String? excludePaperId,
}) async {
  final doi = _normalizeDoiKey(candidate.doi);
  final title = _normalizeTitle(candidate.title);
  final papers = await db.select(db.papers).get();
  for (final paper in papers) {
    if (paper.id == excludePaperId) continue;
    if (doi != null && _normalizeDoiKey(paper.doi) == doi) return paper;
    if (title.isNotEmpty && _normalizeTitle(paper.title) == title) {
      final years = {candidate.year, paper.year}..remove(null);
      if (years.length <= 1) return paper;
    }
  }
  return null;
}

/// Adds a paper from [meta] unless it's already in the library. Returns
/// the new paper's id, or null (and the existing paper in [existing]).
Future<({String? id, Paper? existing})> addPaperFromMetadata(
  AppDatabase db,
  PaperMetadata meta, {
  required String id,
}) async {
  final existing = await findDuplicate(db, meta);
  if (existing != null) return (id: null, existing: existing);
  await db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: Value(id),
          title: meta.title,
          authors: Value(meta.authors),
          year: Value(meta.year),
          venue: Value(meta.venue),
          doi: Value(meta.doi),
        ),
      );
  return (id: id, existing: null);
}

/// Fills in only what's still empty, so a lookup never overwrites what the
/// reader typed. Returns whether anything changed.
Future<bool> fillMissingMetadata(
  AppDatabase db,
  String paperId,
  PaperMetadata meta, {
  bool replaceTitle = false,
}) async {
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(paperId))).getSingleOrNull();
  if (paper == null) return false;
  final companion = PapersCompanion(
    title: replaceTitle && meta.title.isNotEmpty
        ? Value(meta.title)
        : const Value.absent(),
    authors: paper.authors.trim().isEmpty && meta.authors.isNotEmpty
        ? Value(meta.authors)
        : const Value.absent(),
    year: paper.year == null && meta.year != null
        ? Value(meta.year)
        : const Value.absent(),
    venue: (paper.venue ?? '').trim().isEmpty && meta.venue != null
        ? Value(meta.venue)
        : const Value.absent(),
    doi: (paper.doi ?? '').trim().isEmpty && meta.doi != null
        ? Value(meta.doi)
        : const Value.absent(),
  );
  if (companion.title == const Value<String>.absent() &&
      companion.authors == const Value<String>.absent() &&
      companion.year == const Value<int?>.absent() &&
      companion.venue == const Value<String?>.absent() &&
      companion.doi == const Value<String?>.absent()) {
    return false;
  }
  await (db.update(
    db.papers,
  )..where((p) => p.id.equals(paperId))).write(companion);
  return true;
}
