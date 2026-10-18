import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/library/pubmed.dart';

const _esummary = '''
{"header":{"type":"esummary","version":"0.3"},"result":{"uids":["9500320"],
"9500320":{"uid":"9500320","pubdate":"1998 Feb 28","epubdate":"","source":"Lancet",
"authors":[{"name":"Wakefield AJ","authtype":"Author"},
{"name":"Walker-Smith JA","authtype":"Author"},
{"name":"van der Berg AB","authtype":"Author"},
{"name":"ENCODE Consortium","authtype":"CollectiveName"}],
"title":"Ileal-lymphoid-nodular hyperplasia, non-specific colitis, and pervasive developmental disorder in children.",
"articleids":[{"idtype":"pubmed","value":"9500320"},{"idtype":"doi","value":"10.1016/s0140-6736(97)11096-0"}],
"fulljournalname":"Lancet (London, England)"}}}
''';

const _noDoi = '''
{"result":{"uids":["1"],"1":{"uid":"1","pubdate":"2001","source":"J Neurosci",
"authors":[{"name":"Kandel ER"}],"title":"A paper.","articleids":[{"idtype":"pubmed","value":"1"}],
"fulljournalname":""}}}
''';

const _idconv = '''
{"status":"ok","records":[{"doi":"10.1093/nar/gks1195","pmcid":"PMC3531190","pmid":23193287,"requested-id":"PMC3531190"}]}
''';
const _idconvMissing = '''
{"status":"ok","records":[{"pmcid":"PMC99999999","requested-id":"PMC99999999","status":"error","errmsg":"Identifier not found in PMC"}]}
''';
const _crossref = '''
{"status":"ok","message":{"DOI":"10.1093/nar/gks1195","title":["The full Crossref title"],
"container-title":["Nucleic Acids Research"],"author":[{"given":"A","family":"B"}],
"issued":{"date-parts":[[2013]]}}}
''';

PaperIdentifier? p(String s) => parseIdentifier(s);

void main() {
  group('parsing', () {
    test('PMID forms', () {
      const pmid = IdentifierKind.pmid;
      for (final s in [
        'PMID: 12345678',
        'pmid:12345678',
        'PMID12345678',
        'PMID 12345678.',
        'https://pubmed.ncbi.nlm.nih.gov/12345678/',
        'https://pubmed.ncbi.nlm.nih.gov/12345678',
        'https://www.ncbi.nlm.nih.gov/pubmed/12345678',
      ]) {
        expect(p(s), PaperIdentifier(pmid, '12345678'), reason: s);
      }
    });

    test('PMC forms', () {
      const pmc = IdentifierKind.pmc;
      for (final s in [
        'PMC1234567',
        'pmc1234567',
        'PMCID: PMC1234567',
        'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC1234567/',
        'https://pmc.ncbi.nlm.nih.gov/articles/PMC1234567/',
      ]) {
        expect(p(s), PaperIdentifier(pmc, 'PMC1234567'), reason: s);
      }
    });

    test('an unlabelled number is not a PMID', () {
      expect(p('12345678'), isNull);
      expect(p('  20240101 '), isNull);
      expect(p('pages 12345678'), isNull);
      expect(p('PMID'), isNull);
      expect(p('PMC12'), isNull);
    });

    test('a DOI or arXiv id still wins over a PMID in the same text', () {
      expect(p('doi:10.1000/xyz PMID: 123456')!.kind, IdentifierKind.doi);
      expect(p('arXiv:1706.03762 PMID: 5')!.kind, IdentifierKind.arxiv);
    });

    test('PDF text: labelled PMID is found, DOI is preferred', () {
      expect(
        findIdentifierInText('Nature Neuroscience\nPMID: 23193287\nfoo'),
        PaperIdentifier(IdentifierKind.pmid, '23193287'),
      );
      expect(
        findIdentifierInText('PMID: 23193287\ndoi: 10.1093/nar/gks1195'),
        PaperIdentifier(IdentifierKind.doi, '10.1093/nar/gks1195'),
      );
      expect(findIdentifierInText('page 23193287'), isNull);
    });
  });

  group('E-utilities parsing', () {
    test('esummary becomes stored metadata with the DOI', () {
      final r = parsePubmedSummary(_decode(_esummary), '9500320')!;
      expect(r.metadata.title, startsWith('Ileal-lymphoid-nodular'));
      expect(r.metadata.title, isNot(endsWith('.')));
      expect(
        r.metadata.authors,
        'Wakefield, A. J.; Walker-Smith, J. A.; van der Berg, A. B.; ENCODE Consortium',
      );
      expect(r.metadata.year, 1998);
      expect(r.metadata.venue, 'Lancet (London, England)');
      expect(r.metadata.doi, '10.1016/s0140-6736(97)11096-0');
    });

    test('no DOI, journal falls back to the short source', () {
      final r = parsePubmedSummary(_decode(_noDoi), '1')!;
      expect(r.metadata.doi, isNull);
      expect(r.metadata.venue, 'J Neurosci');
      expect(r.metadata.year, 2001);
    });

    test('an unknown id is null', () {
      expect(
        parsePubmedSummary(
          _decode('{"result":{"uids":[],"5":{"error":"cannot get document"}}}'),
          '5',
        ),
        isNull,
      );
      expect(parsePubmedSummary(_decode('{}'), '5'), isNull);
    });

    test('idconv gives PMID and DOI; an error record is null', () {
      final ids = parsePmcConversion(_decode(_idconv))!;
      expect(ids.pmid, '23193287');
      expect(ids.doi, '10.1093/nar/gks1195');
      expect(parsePmcConversion(_decode(_idconvMissing)), isNull);
    });
  });

  group('lookup', () {
    test('PMID with a DOI prefers the Crossref record; https + tool', () async {
      final seen = <Uri>[];
      final lookup = MetadataLookup(
        client: MockClient((req) async {
          seen.add(req.url);
          if (req.url.host == 'api.crossref.org') {
            return http.Response(_crossref, 200);
          }
          return http.Response(_esummary, 200);
        }),
      );
      final meta = await lookup.lookup(
        PaperIdentifier(IdentifierKind.pmid, '9500320'),
      );
      expect(meta!.title, 'The full Crossref title');
      final eutils = seen.firstWhere((u) => u.host.contains('ncbi'));
      expect(eutils.scheme, 'https');
      expect(eutils.queryParameters['tool'], 'corplex');
      expect(eutils.queryParameters['db'], 'pubmed');
      expect(eutils.queryParameters['id'], '9500320');
      expect(eutils.queryParameters.keys, isNot(contains('email')));
    });

    test('falls back to PubMed when Crossref fails or lacks the DOI', () async {
      for (final crossref in [http.Response('', 404), http.Response('', 500)]) {
        final lookup = MetadataLookup(
          client: MockClient(
            (req) async => req.url.host == 'api.crossref.org'
                ? crossref
                : http.Response(_esummary, 200),
          ),
        );
        final meta = await lookup.lookup(
          PaperIdentifier(IdentifierKind.pmid, '9500320'),
        );
        expect(meta!.title, startsWith('Ileal'));
      }
    });

    test('PMC goes through idconv, then Crossref by DOI', () async {
      final hosts = <String>[];
      final lookup = MetadataLookup(
        client: MockClient((req) async {
          hosts.add(req.url.host);
          return req.url.host == 'api.crossref.org'
              ? http.Response(_crossref, 200)
              : http.Response(_idconv, 200);
        }),
      );
      final meta = await lookup.lookup(
        PaperIdentifier(IdentifierKind.pmc, 'PMC3531190'),
      );
      expect(meta!.title, 'The full Crossref title');
      expect(hosts, ['pmc.ncbi.nlm.nih.gov', 'api.crossref.org']);
    });

    test('unknown PMID is null; an unreachable service throws', () async {
      final empty = MetadataLookup(
        client: MockClient(
          (_) async => http.Response('{"result":{"uids":[]}}', 200),
        ),
      );
      expect(
        await empty.lookup(PaperIdentifier(IdentifierKind.pmid, '5')),
        isNull,
      );
      final down = MetadataLookup(
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(
        () => down.lookup(PaperIdentifier(IdentifierKind.pmid, '5')),
        throwsA(isA<LookupFailed>()),
      );
    });
  });
}

Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;
