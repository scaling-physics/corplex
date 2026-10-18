import 'dart:convert';

import 'package:http/http.dart' as http;

import 'authors.dart';
import 'bibtex.dart' show PaperMetadata;
import 'metadata_lookup.dart';

// ---------------------------------------------------------------- parsing

// Only labelled forms count: a bare 8-digit number is far more likely a
// page count, a year range or a phone number than a PubMed id.
final _pmidLabel = RegExp(r'\bpmid\b[\s:#.]*(\d{1,9})\b', caseSensitive: false);
final _pmidGlued = RegExp(r'\bpmid(\d{1,9})\b', caseSensitive: false);
final _pmidUrl = RegExp(
  r'(?:pubmed\.ncbi\.nlm\.nih\.gov|ncbi\.nlm\.nih\.gov/pubmed)/(\d{1,9})\b',
  caseSensitive: false,
);
final _pmcId = RegExp(r'\bPMC(\d{4,9})\b', caseSensitive: false);

/// Recognises a PubMed id (`PMID: 123`, `pmid:123`, `PMID123`, a
/// pubmed.ncbi.nlm.nih.gov link) or a PMC id (`PMC123`, a PMC article
/// link). Returns null for anything unlabelled. A PMID wins over a PMC id.
PaperIdentifier? parsePubmedIdentifier(String input) {
  final text = input.trim();
  final pmid =
      (_pmidUrl.firstMatch(text) ??
              _pmidLabel.firstMatch(text) ??
              _pmidGlued.firstMatch(text))
          ?.group(1);
  if (pmid != null) {
    final n = pmid.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (n != '0') return PaperIdentifier(IdentifierKind.pmid, n);
  }
  final pmc = _pmcId.firstMatch(text)?.group(1);
  if (pmc != null) return PaperIdentifier(IdentifierKind.pmc, 'PMC$pmc');
  return null;
}

// ----------------------------------------------------------------- records

class PubmedRecord {
  const PubmedRecord(this.pmid, this.metadata);
  final String pmid;
  final PaperMetadata metadata;
}

class PmcIds {
  const PmcIds({this.pmid, this.doi});
  final String? pmid;
  final String? doi;
}

/// "Smith JA" -> Smith, J. A.; "van der Berg AB" keeps the particles in the
/// family name; a name without trailing initials (a collective author) is
/// kept whole.
Author parsePubmedAuthor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length > 1 && RegExp(r'^[A-Z]{1,4}$').hasMatch(parts.last)) {
    final initials = parts.last.split('').map((c) => '$c.').join(' ');
    return Author(
      family: parts.sublist(0, parts.length - 1).join(' '),
      given: initials,
    );
  }
  return Author(family: name.trim(), given: '');
}

/// Reads one article out of an `esummary` JSON response. Null when PubMed
/// doesn't know the id or the record has no title.
PubmedRecord? parsePubmedSummary(Map<String, dynamic> json, String pmid) {
  final result = json['result'];
  if (result is! Map) return null;
  final r = result[pmid];
  if (r is! Map || r['error'] != null) return null;
  final title = (r['title'] as String?)
      ?.replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (title == null || title.isEmpty) return null;
  final authors = <Author>[
    for (final a in (r['authors'] as List? ?? const []))
      if (a is Map && (a['name'] as String?)?.trim().isNotEmpty == true)
        parsePubmedAuthor(a['name'] as String),
  ];
  String? doi;
  for (final id in (r['articleids'] as List? ?? const [])) {
    if (id is Map && id['idtype'] == 'doi' && id['value'] is String) {
      doi = (id['value'] as String).trim();
    }
  }
  final year = int.tryParse(
    RegExp(r'\d{4}')
            .firstMatch('${r['pubdate'] ?? r['epubdate'] ?? ''}')
            ?.group(0) ??
        '',
  );
  final venue = [r['fulljournalname'], r['source']]
      .whereType<String>()
      .map((s) => s.trim())
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');
  return PubmedRecord(
    pmid,
    PaperMetadata(
      title: title.endsWith('.') ? title.substring(0, title.length - 1) : title,
      authors: authorsToStored(AuthorList(authors)),
      year: year,
      venue: venue.isEmpty ? null : venue,
      doi: doi,
    ),
  );
}

/// Reads NCBI's ID converter answer. Null when the id isn't found.
PmcIds? parsePmcConversion(Map<String, dynamic> json) {
  final records = json['records'];
  if (records is! List || records.isEmpty) return null;
  final r = records.first;
  if (r is! Map || r['status'] == 'error') return null;
  final pmid = r['pmid']?.toString();
  final doi = r['doi'] as String?;
  if (pmid == null && doi == null) return null;
  return PmcIds(pmid: pmid, doi: doi);
}

// ----------------------------------------------------------------- client

/// NCBI E-utilities and the PMC ID converter, over https, with no key, no
/// email and no personal data (`tool=corplex` only).
class PubmedClient {
  PubmedClient(this._client);

  final http.Client _client;

  static const _timeout = Duration(seconds: 12);

  Future<PubmedRecord?> summary(String pmid) async {
    final response = await _get(
      Uri.https('eutils.ncbi.nlm.nih.gov', '/entrez/eutils/esummary.fcgi', {
        'db': 'pubmed',
        'id': pmid,
        'retmode': 'json',
        'tool': 'corplex',
      }),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw const LookupFailed();
    try {
      return parsePubmedSummary(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        pmid,
      );
    } catch (_) {
      throw const LookupFailed();
    }
  }

  Future<PmcIds?> convertPmc(String pmcid) async {
    final response = await _get(
      Uri.https('pmc.ncbi.nlm.nih.gov', '/tools/idconv/api/v1/articles/', {
        'ids': pmcid,
        'format': 'json',
        'tool': 'corplex',
      }),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw const LookupFailed();
    try {
      return parsePmcConversion(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const LookupFailed();
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_timeout);
    } catch (_) {
      throw const LookupFailed();
    }
  }
}
