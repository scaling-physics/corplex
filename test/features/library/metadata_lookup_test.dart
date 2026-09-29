import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/bibtex.dart';
import 'package:corplex/features/library/metadata_lookup.dart';

const _crossrefBody = '''
{"status":"ok","message":{
  "DOI":"10.1038/nature14539",
  "title":["Deep learning"],
  "container-title":["Nature"],
  "author":[
    {"given":"Yann","family":"LeCun"},
    {"given":"Yoshua","family":"Bengio"},
    {"given":"Geoffrey","family":"Hinton"}],
  "issued":{"date-parts":[[2015,5,27]]}}}
''';

const _arxivBody = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>http://arxiv.org/api/x</id>
  <title>ArXiv Query</title>
  <entry>
    <id>http://arxiv.org/abs/1706.03762v7</id>
    <published>2017-06-12T17:57:34Z</published>
    <title>Attention Is All
  You Need</title>
    <author><name>Ashish Vaswani</name></author>
    <author><name>Noam Shazeer</name></author>
  </entry>
</feed>''';

const _arxivNotFound = '''<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><id>http://arxiv.org/api/errors#x</id><title>Error</title></entry>
</feed>''';

void main() {
  group('parseIdentifier', () {
    test('DOIs in their common shapes', () {
      for (final input in [
        '10.1038/nature14539',
        'doi:10.1038/nature14539',
        'https://doi.org/10.1038/nature14539',
        'See 10.1038/nature14539).',
      ]) {
        expect(
          parseIdentifier(input),
          const PaperIdentifier(IdentifierKind.doi, '10.1038/nature14539'),
          reason: input,
        );
      }
    });

    test('arXiv ids, links and old-style ids; versions dropped', () {
      for (final input in [
        '1706.03762',
        '1706.03762v7',
        'arXiv:1706.03762',
        'https://arxiv.org/abs/1706.03762v2',
        'https://arxiv.org/pdf/1706.03762',
      ]) {
        expect(
          parseIdentifier(input),
          const PaperIdentifier(IdentifierKind.arxiv, '1706.03762'),
          reason: input,
        );
      }
      expect(parseIdentifier('arXiv:hep-th/9901001')?.value, 'hep-th/9901001');
    });

    test('anything else is not an identifier', () {
      expect(parseIdentifier('Attention is all you need'), isNull);
      expect(parseIdentifier(''), isNull);
    });
  });

  test('finds identifiers printed in a PDF\'s text', () {
    expect(
      findIdentifierInText('Nature 521, 436 doi:10.1038/nature14539 © 2015'),
      const PaperIdentifier(IdentifierKind.doi, '10.1038/nature14539'),
    );
    expect(
      findIdentifierInText('arXiv:1706.03762v7 [cs.CL] 2 Aug 2023'),
      const PaperIdentifier(IdentifierKind.arxiv, '1706.03762'),
    );
    expect(findIdentifierInText('No identifiers here.'), isNull);
  });

  group('MetadataLookup', () {
    MetadataLookup withResponse(http.Response Function(http.Request) handler) =>
        MetadataLookup(client: MockClient((req) async => handler(req)));

    test('Crossref: authors, year, venue, DOI', () async {
      Uri? requested;
      final lookup = withResponse((req) {
        requested = req.url;
        return http.Response(_crossrefBody, 200);
      });

      final meta = await lookup.lookup(
        const PaperIdentifier(IdentifierKind.doi, '10.1038/nature14539'),
      );

      expect(requested!.host, 'api.crossref.org');
      expect(requested!.path, '/works/10.1038/nature14539');
      expect(meta!.title, 'Deep learning');
      expect(meta.authors, 'LeCun, Yann; Bengio, Yoshua; Hinton, Geoffrey');
      expect(meta.year, 2015);
      expect(meta.venue, 'Nature');
      expect(meta.doi, '10.1038/nature14539');
    });

    test('Crossref: unknown DOI is null; server trouble throws', () async {
      final id = const PaperIdentifier(IdentifierKind.doi, '10.1/none');
      expect(await withResponse((_) => http.Response('', 404)).lookup(id), isNull);
      await expectLater(
        withResponse((_) => http.Response('', 500)).lookup(id),
        throwsA(isA<LookupFailed>()),
      );
    });

    test('arXiv: title whitespace collapsed, authors and year', () async {
      final meta = await withResponse((_) => http.Response(_arxivBody, 200))
          .lookup(const PaperIdentifier(IdentifierKind.arxiv, '1706.03762'));
      expect(meta!.title, 'Attention Is All You Need');
      expect(meta.authors, 'Vaswani, Ashish; Shazeer, Noam');
      expect(meta.year, 2017);
      expect(meta.venue, 'arXiv:1706.03762');
    });

    test('arXiv: an unknown id is null', () async {
      final meta = await withResponse((_) => http.Response(_arxivNotFound, 200))
          .lookup(const PaperIdentifier(IdentifierKind.arxiv, '0000.00000'));
      expect(meta, isNull);
    });

    test('a network error is a LookupFailed, not a crash', () async {
      final lookup = MetadataLookup(
        client: MockClient((_) async => throw Exception('offline')),
      );
      await expectLater(
        lookup.lookup(const PaperIdentifier(IdentifierKind.doi, '10.1/x')),
        throwsA(isA<LookupFailed>()),
      );
    });

    test('Crossref titles lose markup', () {
      final meta = parseCrossref(
        jsonDecode(
              '{"message":{"title":["The <i>E. coli</i> genome"],"issued":{"date-parts":[[2020]]}}}',
            )
            as Map<String, dynamic>,
      );
      expect(meta!.title, 'The E. coli genome');
    });
  });

  group('duplicates', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.inMemoryForTesting();
      await db.into(db.papers).insert(
        PapersCompanion.insert(
          id: const Value('p1'),
          title: 'Attention Is All You Need',
          year: const Value(2017),
          doi: const Value('10.5555/3295222.3295349'),
        ),
      );
    });
    tearDown(() => db.close());

    test('same DOI, however written', () async {
      final dup = await findDuplicate(
        db,
        const PaperMetadata(
          title: 'Something else entirely',
          doi: 'https://doi.org/10.5555/3295222.3295349',
        ),
      );
      expect(dup?.id, 'p1');
    });

    test('same title ignoring case and punctuation', () async {
      final dup = await findDuplicate(
        db,
        const PaperMetadata(title: 'attention is  ALL you need!'),
      );
      expect(dup?.id, 'p1');
    });

    test('same title but a different year is a different paper', () async {
      final dup = await findDuplicate(
        db,
        const PaperMetadata(title: 'Attention Is All You Need', year: 2021),
      );
      expect(dup, isNull);
    });

    test('a paper is not a duplicate of itself', () async {
      final dup = await findDuplicate(
        db,
        const PaperMetadata(title: 'Attention Is All You Need'),
        excludePaperId: 'p1',
      );
      expect(dup, isNull);
    });

    test('addPaperFromMetadata refuses duplicates', () async {
      final again = await addPaperFromMetadata(
        db,
        const PaperMetadata(title: 'Attention Is All You Need'),
        id: 'p2',
      );
      expect(again.id, isNull);
      expect(again.existing?.id, 'p1');

      final fresh = await addPaperFromMetadata(
        db,
        const PaperMetadata(title: 'BERT', authors: 'Devlin, Jacob', year: 2018),
        id: 'p3',
      );
      expect(fresh.id, 'p3');
      expect(await db.select(db.papers).get(), hasLength(2));
    });

    test('fillMissingMetadata only fills what is empty', () async {
      await db.into(db.papers).insert(
        PapersCompanion.insert(
          id: const Value('p9'),
          title: 'My own title',
          authors: const Value('Typed, Myself'),
        ),
      );
      final changed = await fillMissingMetadata(
        db,
        'p9',
        const PaperMetadata(
          title: 'Their title',
          authors: 'Other, Person',
          year: 2015,
          venue: 'Nature',
          doi: '10.1/x',
        ),
      );
      expect(changed, isTrue);
      final paper = await (db.select(db.papers)..where((p) => p.id.equals('p9'))).getSingle();
      expect(paper.title, 'My own title');
      expect(paper.authors, 'Typed, Myself');
      expect(paper.year, 2015);
      expect(paper.venue, 'Nature');
      expect(paper.doi, '10.1/x');

      // Nothing left to fill.
      expect(
        await fillMissingMetadata(db, 'p9', const PaperMetadata(title: 'x', year: 1999)),
        isFalse,
      );
    });
  });
}
