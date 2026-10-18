import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/highlights.dart';
import 'package:corplex/features/zotero/zotero_client.dart';
import 'package:corplex/features/zotero/zotero_import.dart';
import 'package:corplex/features/zotero/zotero_mapping.dart';

Map<String, dynamic> item(String key, Map<String, dynamic> data) => {
  'key': key,
  'data': {'key': key, ...data},
};

Map<String, dynamic> article(
  String key, {
  String title = 'Deep learning',
  List<String> collections = const [],
  String? doi = '10.1038/nature14539',
}) => item(key, {
  'itemType': 'journalArticle',
  'title': title,
  'creators': [
    {'creatorType': 'author', 'firstName': 'Yann', 'lastName': 'LeCun'},
    {'creatorType': 'author', 'firstName': 'Yoshua', 'lastName': 'Bengio'},
    {'creatorType': 'editor', 'firstName': 'Ed', 'lastName': 'Itor'},
  ],
  'date': '2015-05-27',
  'publicationTitle': 'Nature',
  'DOI': ?doi,
  'collections': collections,
});

class Fixture {
  Fixture({
    this.collections = const [],
    this.top = const [],
    this.attachments = const [],
    this.annotations = const [],
    this.notes = const [],
  });
  List<Map<String, dynamic>> collections, top, attachments, annotations, notes;
  final requests = <Uri>[];
  final headersSeen = <Map<String, String>>[];
  Map<String, Uint8List?> files = {};
  int pageLimit = 100;
  int failNextWith = 0;

  MockClient get client => MockClient((req) async {
    requests.add(req.url);
    headersSeen.add(req.headers);
    if (failNextWith != 0) {
      final code = failNextWith;
      failNextWith = 0;
      return http.Response('', code, headers: {'retry-after': '1'});
    }
    final path = req.url.path;
    final m = RegExp(r'^/users/42/items/(\w+)/file$').firstMatch(path);
    if (m != null) {
      final f = files[m.group(1)];
      return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
    }
    List<Map<String, dynamic>> all;
    if (path.endsWith('/collections')) {
      all = collections;
    } else if (path.endsWith('/items/top')) {
      all = top;
    } else {
      all = switch (req.url.queryParameters['itemType']) {
        'attachment' => attachments,
        'annotation' => annotations,
        _ => notes,
      };
    }
    final start = int.parse(req.url.queryParameters['start'] ?? '0');
    final limit = int.parse(req.url.queryParameters['limit'] ?? '100');
    final slice = all.skip(start).take(limit <= pageLimit ? limit : pageLimit);
    return http.Response(
      jsonEncode(slice.toList()),
      200,
      headers: {'total-results': '${all.length}'},
    );
  });
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  setUp(() {
    db = AppDatabase.inMemoryForTesting();
    tmp = Directory.systemTemp.createTempSync('zotero');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  ZoteroClient clientFor(Fixture f, {int? maxFile}) => ZoteroClient(
    userId: '42',
    apiKey: 'secret',
    client: f.client,
    delay: (_) async {},
    maxFileBytes: maxFile ?? 50 * 1024 * 1024,
  );

  ZoteroImporter importer(Fixture f, {List<Size>? sizes}) => ZoteroImporter(
    db: db,
    client: clientFor(f),
    pageSizes: (_) async => sizes,
    savePdf: (bytes, name) async {
      final file = File(
        '${tmp.path}/${DateTime.now().microsecondsSinceEpoch}$name',
      );
      await file.writeAsBytes(bytes);
      return file.path;
    },
  );

  group('mapping', () {
    test('creators, year, venue, doi', () {
      final m = paperFromZoteroItem(article('A'))!;
      expect(m.title, 'Deep learning');
      expect(m.authors, 'LeCun, Yann; Bengio, Yoshua');
      expect(m.year, 2015);
      expect(m.venue, 'Nature');
      expect(m.doi, '10.1038/nature14539');
    });

    test('venue fallbacks, single-field names, doi from extra', () {
      final m = paperFromZoteroItem(
        item('B', {
          'itemType': 'conferencePaper',
          'title': 'T',
          'creators': [
            {'creatorType': 'author', 'name': 'DeepMind'},
          ],
          'date': 'Spring 2019',
          'proceedingsTitle': 'NeurIPS',
          'extra': 'DOI: 10.1/abc',
        }),
      )!;
      expect(m.authors, 'DeepMind');
      expect(m.year, 2019);
      expect(m.venue, 'NeurIPS');
      expect(m.doi, '10.1/abc');
    });

    test('notes, attachments and untitled items are not papers', () {
      expect(paperFromZoteroItem(item('N', {'itemType': 'note'})), isNull);
      expect(
        paperFromZoteroItem(
          item('X', {'itemType': 'attachment', 'title': 'a'}),
        ),
        isNull,
      );
      expect(paperFromZoteroItem(item('U', {'itemType': 'book'})), isNull);
    });

    test('rects become top-left page fractions', () {
      final r = rectsToFractions([
        [60, 700, 300, 720],
      ], const Size(600, 800));
      expect(r.single.left, closeTo(0.1, 1e-9));
      expect(r.single.right, closeTo(0.5, 1e-9));
      expect(r.single.top, closeTo(0.1, 1e-9));
      expect(r.single.bottom, closeTo(0.125, 1e-9));
      expect(
        rectsToFractions([
          [0, 0, 1, 1],
        ], null),
        isEmpty,
      );
    });

    test('colour maps to nearest ink', () {
      expect(nearestInk('#ffd400'), highlightInks[0]);
      expect(nearestInk('#5fb236'), highlightInks[1]);
      expect(nearestInk('#ff6666'), highlightInks[2]);
      expect(nearestInk('#2ea8e5'), highlightInks[3]);
      expect(nearestInk(null), highlightInks[0]);
    });

    test('html to text', () {
      expect(
        htmlToPlainText(
          '<p>Fish &amp; chips</p><ul><li>one</li><li>two</li></ul>',
        ),
        'Fish & chips\n• one\n• two',
      );
    });

    test('collections are flattened', () {
      final list = parseCollections([
        item('C2', {'name': 'Child', 'parentCollection': 'C1'}),
        item('C1', {'name': 'Parent', 'parentCollection': false}),
      ]);
      expect([for (final c in list) c.path], ['Parent', 'Parent / Child']);
      expect(list[1].depth, 1);
    });
  });

  group('client', () {
    test('sends headers over https and paginates', () async {
      final f = Fixture(
        top: [for (var i = 0; i < 250; i++) article('K$i', title: 'T$i')],
      )..pageLimit = 100;
      final items = await clientFor(f).topItems();
      expect(items, hasLength(250));
      expect(f.requests, hasLength(3));
      expect(f.requests.every((u) => u.scheme == 'https'), isTrue);
      expect(f.headersSeen.first['Zotero-API-Version'], '3');
      expect(f.headersSeen.first['Zotero-API-Key'], 'secret');
      expect(f.requests[1].queryParameters['start'], '100');
    });

    test('retries after a 429 using Retry-After', () async {
      final f = Fixture(collections: [])..failNextWith = 429;
      final waits = <Duration>[];
      final c = ZoteroClient(
        userId: '42',
        apiKey: 'k',
        client: f.client,
        delay: (d) async => waits.add(d),
      );
      await c.check();
      expect(waits, [const Duration(seconds: 1)]);
    });

    test('gives up with a rate-limit message', () async {
      final client = MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '1'}),
      );
      final c = ZoteroClient(
        userId: '42',
        apiKey: 'k',
        client: client,
        delay: (_) async {},
      );
      await expectLater(
        c.check(),
        throwsA(
          isA<ZoteroException>().having(
            (e) => e.problem,
            'problem',
            ZoteroProblem.rateLimited,
          ),
        ),
      );
    });

    test('bad key, missing library, offline', () async {
      ZoteroClient with_(http.Client c) => ZoteroClient(
        userId: '42',
        apiKey: 'k',
        client: c,
        delay: (_) async {},
      );
      Future<ZoteroProblem> problem(http.Client c) async {
        try {
          await with_(c).check();
        } on ZoteroException catch (e) {
          return e.problem;
        }
        fail('should have thrown');
      }

      expect(
        await problem(MockClient((_) async => http.Response('', 403))),
        ZoteroProblem.badKey,
      );
      expect(
        await problem(MockClient((_) async => http.Response('', 404))),
        ZoteroProblem.notFound,
      );
      expect(
        await problem(
          MockClient((_) async => throw const SocketException('down')),
        ),
        ZoteroProblem.offline,
      );
    });

    test('file download respects the size cap and 404', () async {
      final f = Fixture()..files = {'BIG': Uint8List(100), 'NONE': null};
      final c = clientFor(f, maxFile: 50);
      expect(await c.downloadFile('BIG'), isNull);
      expect(await c.downloadFile('NONE'), isNull);
      f.files['OK'] = Uint8List(10);
      expect(await c.downloadFile('OK'), hasLength(10));
    });
  });

  group('import', () {
    Fixture library() {
      final f = Fixture(
        collections: [
          item('C1', {'name': 'Thesis', 'parentCollection': false})
            ..['meta'] = {'numItems': 2},
          item('C2', {'name': 'Ch 1', 'parentCollection': 'C1'}),
        ],
        top: [
          article('P1', collections: ['C2']),
          article('P2', title: 'Attention is all you need', doi: null)
            ..['data']['date'] = '2017',
          item('N0', {'itemType': 'note', 'note': '<p>loose</p>'}),
        ],
        attachments: [
          item('A1', {
            'itemType': 'attachment',
            'parentItem': 'P1',
            'contentType': 'application/pdf',
            'linkMode': 'imported_file',
            'filename': 'lecun.pdf',
          }),
          item('A2', {
            'itemType': 'attachment',
            'parentItem': 'P2',
            'contentType': 'text/html',
            'linkMode': 'imported_url',
          }),
        ],
        annotations: [
          item('H1', {
            'itemType': 'annotation',
            'parentItem': 'A1',
            'annotationType': 'highlight',
            'annotationText': 'Deep   learning allows',
            'annotationComment': 'key idea',
            'annotationColor': '#5fb236',
            'annotationPosition': jsonEncode({
              'pageIndex': 2,
              'rects': [
                [60, 700, 300, 720],
              ],
            }),
          }),
          item('H2', {
            'itemType': 'annotation',
            'parentItem': 'A1',
            'annotationType': 'note',
            'annotationComment': 'check this',
            'annotationPosition': jsonEncode({'pageIndex': 0, 'rects': []}),
          }),
          item('H3', {
            'itemType': 'annotation',
            'parentItem': 'A1',
            'annotationType': 'image',
            'annotationPosition': '{}',
          }),
        ],
        notes: [
          item('M1', {
            'itemType': 'note',
            'parentItem': 'P1',
            'note': '<p>Great <b>paper</b></p>',
          }),
        ],
      );
      f.files = {
        'A1': Uint8List.fromList([37, 80, 68, 70]),
      };
      return f;
    }

    final sizes = [
      const Size(600, 800),
      const Size(600, 800),
      const Size(600, 800),
    ];

    test('papers, pdf, highlights, projects, notes, summary', () async {
      final f = library();
      final progress = <ZoteroProgress>[];
      final s = await importer(f, sizes: sizes).run(onProgress: progress.add);
      expect(s.papers, 2);
      expect(s.pdfs, 1);
      expect(s.highlights, 1);
      expect(s.projects, {'Thesis', 'Thesis / Ch 1'}.intersection(s.projects));
      expect(
        s.message,
        startsWith('Imported 2 papers, 1 PDF, 1 highlight into'),
      );
      expect(progress, isNotEmpty);

      final papers = await db.select(db.papers).get();
      final p1 = papers.firstWhere((p) => p.title == 'Deep learning');
      expect(p1.authors, 'LeCun, Yann; Bengio, Yoshua');
      expect(p1.citekey, isNotNull);
      expect(p1.pdfPath, isNotNull);
      expect(File(p1.pdfPath!).existsSync(), isTrue);
      expect(p1.pageCount, 3);
      expect(
        papers.firstWhere((p) => p.title.startsWith('Attention')).pdfPath,
        isNull,
      );

      final h = await db.select(db.highlights).getSingle();
      expect(h.pageNumber, 3);
      expect(h.quote, 'Deep learning allows');
      expect(h.comment, 'key idea');
      expect(h.colorHex, colorToHex(highlightInks[1]));
      final rect = decodeRects(h.rectsJson).single;
      expect(rect.left, closeTo(0.1, 1e-3));
      expect(rect.top, closeTo(0.1, 1e-3));

      final projects = await db.select(db.projects).get();
      expect(projects.map((p) => p.name), contains('Thesis / Ch 1'));
      expect(await db.select(db.projectPapers).get(), hasLength(1));

      final note = await db.select(db.notes).getSingle();
      expect(note.title, 'Zotero notes: Deep learning');
      expect(note.content, contains('Great paper'));
      expect(note.content, contains('p. 1: check this'));
      expect(await db.select(db.notePaperRefs).get(), hasLength(1));
    });

    test('re-import duplicates nothing', () async {
      final f = library();
      await importer(f, sizes: sizes).run();
      final s = await importer(f, sizes: sizes).run();
      expect(s.papers, 0);
      expect(s.alreadyInLibrary, 2);
      expect(s.pdfs, 0);
      expect(s.highlights, 0);
      expect(s.notes, 0);
      expect(await db.select(db.papers).get(), hasLength(2));
      expect(await db.select(db.highlights).get(), hasLength(1));
      expect(await db.select(db.notes).get(), hasLength(1));
      expect(s.message, contains('2 already in your library'));
    });

    test('existing paper keeps its fields, gains missing ones', () async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              title: 'Deep learning',
              venue: const Value('My venue'),
              doi: const Value('10.1038/nature14539'),
            ),
          );
      await importer(library(), sizes: sizes).run();
      final p = (await db.select(db.papers).get()).firstWhere(
        (p) => p.title == 'Deep learning',
      );
      expect(p.venue, 'My venue');
      expect(p.authors, 'LeCun, Yann; Bengio, Yoshua');
      expect(p.year, 2015);
      expect(await db.select(db.papers).get(), hasLength(2));
    });

    test('unknown page size keeps the highlight without rects', () async {
      final s = await importer(library(), sizes: null).run();
      expect(s.highlights, 1);
      final h = await db.select(db.highlights).getSingle();
      expect(decodeRects(h.rectsJson), isEmpty);
    });

    test('only chosen collections (with children) are imported', () async {
      final f = library();
      final s = await importer(f, sizes: sizes).run(collectionKeys: {'C1'});
      expect(s.papers, 1);
      expect((await db.select(db.papers).getSingle()).title, 'Deep learning');
    });

    test('a failed PDF download still imports the paper', () async {
      final f = library()..files = {};
      final s = await importer(f, sizes: sizes).run();
      expect(s.papers, 2);
      expect(s.pdfs, 0);
      expect(s.pdfsFailed, 1);
      expect(s.message, contains("1 PDF couldn't be downloaded"));
    });

    test('cancel stops before importing', () async {
      var calls = 0;
      final s = await importer(
        library(),
        sizes: sizes,
      ).run(isCancelled: () => ++calls > 3);
      expect(s.cancelled, isTrue);
      expect(s.papers, lessThan(2));
      expect(s.message, startsWith('Stopped.'));
    });

    test('a bad key aborts with a clear error', () async {
      final c = ZoteroClient(
        userId: '42',
        apiKey: 'bad',
        client: MockClient((_) async => http.Response('', 403)),
        delay: (_) async {},
      );
      await expectLater(
        ZoteroImporter(db: db, client: c).run(),
        throwsA(isA<ZoteroException>()),
      );
      expect(await db.select(db.papers).get(), isEmpty);
    });
  });
}
