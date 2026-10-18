import 'dart:convert';

import 'authors.dart';
import 'bibtex.dart';
import 'pubmed.dart' show pubmedIdFromUrl;

/// Reads reference-manager exports: BibTeX, RIS (Zotero, Mendeley, EndNote,
/// most publishers) and CSL JSON (Zotero's "CSL JSON"). The format is
/// sniffed from the content, so the file extension doesn't matter.
List<PaperMetadata> parseReferences(String source) {
  final text = source.trimLeft();
  if (text.startsWith('[') || text.startsWith('{')) {
    final csl = parseCslJson(text);
    if (csl != null) return csl;
  }
  if (RegExp(r'^TY {1,2}- ', multiLine: true).hasMatch(source)) {
    return parseRis(source);
  }
  return parseBibtex(source);
}

/// RIS: `TAG  - value` lines, records from `TY` to `ER`. Repeatable tags
/// (authors) accumulate; a continuation line without a tag extends the
/// previous value.
List<PaperMetadata> parseRis(String source) {
  final results = <PaperMetadata>[];
  var record = <String, List<String>>{};
  String? lastTag;

  void finish() {
    final paper = _fromRis(record);
    if (paper != null) results.add(paper);
    record = {};
    lastTag = null;
  }

  final tagLine = RegExp(r'^([A-Z][A-Z0-9])  ?-\s?(.*)$');
  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.replaceAll('﻿', '').trimRight();
    final m = tagLine.firstMatch(line);
    if (m == null) {
      if (line.trim().isNotEmpty &&
          lastTag != null &&
          record[lastTag] != null) {
        record[lastTag]!.last = '${record[lastTag]!.last} ${line.trim()}';
      }
      continue;
    }
    final tag = m.group(1)!;
    final value = m.group(2)!.trim();
    if (tag == 'TY') {
      if (record.isNotEmpty) finish(); // a record missing its ER
    }
    if (tag == 'ER') {
      finish();
      continue;
    }
    if (value.isEmpty) continue;
    record.putIfAbsent(tag, () => []).add(value);
    lastTag = tag;
  }
  if (record.isNotEmpty) finish();
  return results;
}

PaperMetadata? _fromRis(Map<String, List<String>> r) {
  String? first(List<String> tags) {
    for (final t in tags) {
      final v = r[t];
      if (v != null && v.isNotEmpty) return v.first;
    }
    return null;
  }

  final title = first(['TI', 'T1', 'CT']);
  if (title == null || title.isEmpty) return null;

  final authors = <Author>[];
  for (final tag in const ['AU', 'A1']) {
    for (final name in r[tag] ?? const <String>[]) {
      // RIS authors are "Family, Given" (sometimes "Given Family").
      authors.addAll(parseAuthors(name).authors);
    }
  }

  final date = first(['PY', 'Y1', 'DA']);
  final year = date == null
      ? null
      : int.tryParse(RegExp(r'\d{4}').firstMatch(date)?.group(0) ?? '');

  final doi = first(['DO', 'DI']);
  final ur = first(['UR', 'L1', 'L2']);
  // AN / C1 / M1 / ID hold a PubMed id in PubMed's own export; elsewhere an
  // accession number, so only a plain run of digits counts.
  String? pmid;
  for (final tag in const ['AN', 'C1', 'M1', 'N1']) {
    for (final v in r[tag] ?? const <String>[]) {
      final m =
          RegExp(
            r'^(?:pmid[:\s]*)?(\d{1,9})$',
            caseSensitive: false,
          ).firstMatch(v.trim()) ??
          RegExp(r'\bpmid[:\s]*(\d{1,9})', caseSensitive: false).firstMatch(v);
      if (m != null) {
        pmid = m.group(1);
        break;
      }
    }
    if (pmid != null) break;
  }
  pmid ??= pubmedIdFromUrl(ur);
  final abstract = first(['AB', 'N2']);
  return PaperMetadata(
    title: title,
    authors: authorsToStored(AuthorList(authors)),
    year: year,
    venue: first(['JO', 'JF', 'JA', 'T2', 'BT', 'JT']),
    doi: doi == null || doi.isEmpty
        ? _doiFromUrl(first(['UR']))
        : _normDoi(doi),
    pmid: pmid,
    url: _linkOrNull(ur),
    abstract: abstract == null || abstract.trim().isEmpty ? null : abstract,
  );
}

/// A web link worth keeping: not just the DOI's own resolver address.
String? _linkOrNull(String? url) {
  final u = url?.trim();
  if (u == null || u.isEmpty) return null;
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(u)) return null;
  if (RegExp(r'^https?://(dx\.)?doi\.org/', caseSensitive: false).hasMatch(u)) {
    return null;
  }
  return u;
}

String? _doiFromUrl(String? url) {
  if (url == null) return null;
  final m = RegExp(r'doi\.org/(10\.\S+)', caseSensitive: false).firstMatch(url);
  return m?.group(1);
}

String _normDoi(String raw) => raw.trim().replaceFirst(
  RegExp(r'^(https?://(dx\.)?doi\.org/|doi:\s*)', caseSensitive: false),
  '',
);

/// CSL JSON: a list of items, or one item. Null if it isn't CSL JSON.
List<PaperMetadata>? parseCslJson(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return null;
  }
  final items = decoded is List ? decoded : [decoded];
  final results = <PaperMetadata>[];
  for (final item in items) {
    if (item is! Map) return results.isEmpty ? null : results;
    final title = (item['title'] as Object?)?.toString().trim() ?? '';
    if (title.isEmpty) continue;
    final authors = [
      for (final a in (item['author'] as List? ?? const []))
        if (a is Map)
          if (a['family'] != null || a['literal'] != null)
            Author(
              family: (a['family'] ?? a['literal']).toString(),
              given: (a['given'] ?? '').toString(),
            ),
    ];
    int? year;
    final parts =
        ((item['issued'] as Map?)?['date-parts'] as List?)?.firstOrNull;
    if (parts is List && parts.isNotEmpty) {
      year = int.tryParse('${parts.first}');
    }
    final doi = item['DOI']?.toString();
    final pmidRaw = item['PMID']?.toString().trim() ?? '';
    final abstract = item['abstract']?.toString().trim() ?? '';
    final venue = (item['container-title'] ?? item['publisher'])?.toString();
    results.add(
      PaperMetadata(
        title: title,
        authors: authorsToStored(AuthorList(authors)),
        year: year,
        venue: venue == null || venue.isEmpty ? null : venue,
        doi: doi == null || doi.isEmpty ? null : _normDoi(doi),
        pmid: RegExp(r'^\d{1,9}$').hasMatch(pmidRaw) ? pmidRaw : null,
        url: _linkOrNull(item['URL']?.toString()),
        abstract: abstract.isEmpty ? null : abstract,
      ),
    );
  }
  return results;
}
