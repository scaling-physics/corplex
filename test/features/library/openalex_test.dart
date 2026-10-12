import 'dart:convert';
import 'dart:io';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/library/citation_network_section.dart';
import 'package:corplex/features/library/bibtex.dart' show PaperMetadata;
import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/library/openalex.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/library/paper_detail_screen.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_audio_engine.dart';

Map<String, dynamic> _w(
  String id,
  String title,
  int year,
  String? doi, {
  List<String> authors = const ['Ada Lovelace'],
  String? venue = 'Nature',
}) => {
  'id': 'https://openalex.org/$id',
  'title': title,
  'publication_year': year,
  'doi': doi == null ? null : 'https://doi.org/$doi',
  'authorships': [
    for (final a in authors)
      {
        'author': {'display_name': a},
      },
  ],
  'primary_location': {
    'source': venue == null ? null : {'display_name': venue},
  },
};

final _work = {
  'id': 'https://openalex.org/W100',
  'title': 'Attention Is All You Need',
  'cited_by_count': 3,
  'referenced_works': [
    'https://openalex.org/W1',
    'https://openalex.org/W2',
    'https://openalex.org/W3',
  ],
};

/// A fake OpenAlex that counts requests.
class _Server {
  final cited = 30;
  final requests = <Uri>[];
  var offline = false;
  var known = true;

  http.Client get client => MockClient((req) async {
    requests.add(req.url);
    if (offline) throw const SocketException('offline');
    expect(req.url.scheme, 'https');
    expect(req.url.host, 'api.openalex.org');
    expect(req.url.toString(), isNot(contains('mailto')));
    final path = req.url.path;
    final q = req.url.queryParameters;
    if (path.startsWith('/works/doi:')) {
      return known
          ? http.Response(jsonEncode(_work), 200)
          : http.Response('{}', 404);
    }
    final filter = q['filter']!;
    if (filter.startsWith('openalex_id:')) {
      final ids = filter.substring(12).split('|');
      final all = {
        'W1': _w('W1', 'Neural Machine Translation', 2014, '10.1000/nmt'),
        'W2': _w('W2', 'Layer Normalization', 2016, null, venue: null),
        // W3 deliberately missing: OpenAlex can't resolve it.
      };
      return http.Response(
        jsonEncode({
          'results': [
            for (final id in ids)
              if (all[id] != null) all[id],
          ],
        }),
        200,
      );
    }
    final page = int.parse(q['page']!);
    final from = (page - 1) * 25;
    final to = (from + 25).clamp(0, cited);
    return http.Response(
      jsonEncode({
        'meta': {'count': cited},
        'results': [
          for (var i = from; i < to; i++)
            _w('W${1000 + i}', 'Citing paper $i', 2020, '10.9000/c$i'),
        ],
      }),
      200,
    );
  });
}

class _MemoryCache extends CitationCache {
  _MemoryCache(super.dir, {super.now});
  final store = <String, CitationRecord>{};
  @override
  Future<CitationRecord?> read(String doi) async => store[doi];
  @override
  Future<void> write(CitationRecord r) async => store[r.doi] = r;
}

void main() {
  group('parsing', () {
    test('a work keeps authors, year, venue and a bare lowercase DOI', () {
      final w = parseOpenAlexWork(
        _w('W1', 'Neural MT', 2014, '10.1000/NMT', authors: ['A B', 'C D']),
      )!;
      expect(w.id, 'W1');
      expect(w.authors, ['A B', 'C D']);
      expect(w.year, 2014);
      expect(w.venue, 'Nature');
      expect(w.doi, '10.1000/nmt');
      expect(w.toMetadata().authors, 'B, A; D, C');
    });

    test('missing venue, DOI and authors are fine; no title is skipped', () {
      final w = parseOpenAlexWork(
        _w('W2', 'Bare', 2000, null, authors: [], venue: null),
      )!;
      expect(w.venue, isNull);
      expect(w.doi, isNull);
      expect(w.authorsLine, '');
      expect(parseOpenAlexWork({'id': 'x', 'title': null}), isNull);
    });

    test('arXiv ids and DOIs normalise to the same key', () {
      expect(
        normalizeCitationDoi('arXiv:1706.03762'),
        '10.48550/arxiv.1706.03762',
      );
      expect(
        normalizeCitationDoi('https://doi.org/10.48550/arXiv.1706.03762'),
        '10.48550/arxiv.1706.03762',
      );
      expect(normalizeCitationDoi(''), isNull);
      expect(normalizeCitationDoi('not an id'), isNull);
    });
  });

  group('client', () {
    test('references resolve in order, skipping unresolvable ones', () async {
      final s = _Server();
      final c = OpenAlexClient(client: s.client);
      final w = (await c.work('10.48550/arXiv.1706.03762'))!;
      expect(w.id, 'W100');
      expect(w.referenced, ['W1', 'W2', 'W3']);
      final refs = await c.worksByIds(w.referenced);
      expect(
        [for (final r in refs) r.title],
        ['Neural Machine Translation', 'Layer Normalization'],
      );
      final cited = s.requests.first.path;
      expect(cited, contains('10.48550/arXiv.1706.03762'));
    });

    test('cited by is sorted by citation count and paged', () async {
      final s = _Server();
      final c = OpenAlexClient(client: s.client);
      final p1 = await c.citedBy('W100');
      expect(p1.items, hasLength(25));
      expect(p1.total, 30);
      expect(s.requests.last.queryParameters['sort'], 'cited_by_count:desc');
      final p2 = await c.citedBy('W100', page: 2);
      expect(p2.items, hasLength(5));
    });

    test('unknown work is null; unreachable or server error throws', () async {
      final s = _Server()..known = false;
      final c = OpenAlexClient(client: s.client);
      expect(await c.work('10.1000/none'), isNull);
      s.offline = true;
      expect(() => c.work('10.1000/x'), throwsA(isA<LookupFailed>()));
      final broken = OpenAlexClient(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      expect(() => broken.citedBy('W1'), throwsA(isA<LookupFailed>()));
      final garbage = OpenAlexClient(
        client: MockClient((_) async => http.Response('<html>', 200)),
      );
      expect(() => garbage.citedBy('W1'), throwsA(isA<LookupFailed>()));
    });
  });

  group('network + cache', () {
    late _Server server;
    late _MemoryCache cache;
    late DateTime clock;
    late CitationNetwork net;
    setUp(() {
      server = _Server();
      clock = DateTime.utc(2026, 10, 1);
      cache = _MemoryCache(() async => Directory.systemTemp, now: () => clock);
      net = CitationNetwork(OpenAlexClient(client: server.client), cache);
    });

    test('second load is served from the cache', () async {
      final r = (await net.load('10.1000/Attn'))!;
      expect(r.references, hasLength(2));
      expect(r.referenceCount, 3);
      expect(r.cited, hasLength(25));
      final n = server.requests.length;
      await net.load('10.1000/attn');
      expect(server.requests.length, n);
    });

    test('expires after 30 days and on refresh', () async {
      await net.load('10.1000/attn');
      final n = server.requests.length;
      clock = clock.add(const Duration(days: 29));
      await net.load('10.1000/attn');
      expect(server.requests.length, n);
      await net.load('10.1000/attn', refresh: true);
      expect(server.requests.length, greaterThan(n));
      final m = server.requests.length;
      clock = clock.add(const Duration(days: 31));
      await net.load('10.1000/attn');
      expect(server.requests.length, greaterThan(m));
    });

    test('stale cache is used offline, but refresh reports it', () async {
      await net.load('10.1000/attn');
      clock = clock.add(const Duration(days: 40));
      server.offline = true;
      expect(await net.load('10.1000/attn'), isNotNull);
      expect(
        () => net.load('10.1000/attn', refresh: true),
        throwsA(isA<LookupFailed>()),
      );
    });

    test('not found is null and unreachable throws', () async {
      server.known = false;
      expect(await net.load('10.1000/none'), isNull);
      server.offline = true;
      expect(() => net.load('10.1000/other'), throwsA(isA<LookupFailed>()));
    });

    test('load more appends the next page and caches it', () async {
      final r = (await net.load('10.1000/attn'))!;
      expect(r.hasMoreCited, isTrue);
      final more = await net.loadMoreCited(r);
      expect(more.cited, hasLength(30));
      expect(more.hasMoreCited, isFalse);
      expect((await cache.read('10.1000/attn'))!.cited, hasLength(30));
    });

    test('file cache round-trips', () async {
      final dir = await Directory.systemTemp.createTemp('oa');
      addTearDown(() => dir.delete(recursive: true));
      final fileCache = CitationCache(() async => dir);
      await net.load('10.1000/attn');
      final rec = cache.store['10.1000/attn']!;
      await fileCache.write(rec);
      final back = (await fileCache.read('10.1000/attn'))!;
      expect(back.references.first.title, 'Neural Machine Translation');
      expect(back.citedTotal, 30);
      expect(await fileCache.read('10.1000/zzz'), isNull);
    });
  });

  group('section', () {
    late AppDatabase db;
    late _Server server;

    setUp(() {
      EditableText.debugDeterministicCursor = true;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      server = _Server();
    });
    tearDown(() {
      EditableText.debugDeterministicCursor = false;
      db.close();
    });

    List<Override> overrides() => [
      databaseProvider.overrideWithValue(db),
      openAlexClientProvider.overrideWithValue(
        OpenAlexClient(client: server.client),
      ),
      citationCacheProvider.overrideWithValue(
        _MemoryCache(() async => Directory.systemTemp),
      ),
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      coverRendererProvider.overrideWithValue((_) async => null),
    ];

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Future<void> showSection(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CitationNetworkSection(doi: '10.1000/attn'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('nothing is fetched until opened; items are marked/added', (
      tester,
    ) async {
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p9'),
              title: 'Neural Machine Translation',
              doi: const Value('10.1000/NMT'),
            ),
          );
      await showSection(tester);
      expect(server.requests, isEmpty);
      expect(find.text('Neural Machine Translation'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('citation-network-toggle')));
      await tester.pumpAndSettle();
      expect(server.requests, isNotEmpty);
      expect(find.text('Neural Machine Translation'), findsOneWidget);
      expect(find.text('Layer Normalization'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
      final titles = [
        for (final p in await db.select(db.papers).get()) p.title,
      ];
      expect(titles, contains('Layer Normalization'));
      expect(titles, hasLength(2));

      await tester.tap(find.text('Cited by 30'));
      await tester.pumpAndSettle();
      expect(find.text('Citing paper 0'), findsOneWidget);
      await close(tester);
    });

    testWidgets('adding something already there is caught as a duplicate', (
      tester,
    ) async {
      await showSection(tester);
      await tester.tap(find.byKey(const ValueKey('citation-network-toggle')));
      await tester.pumpAndSettle();
      // Added elsewhere (e.g. by a DOI lookup) after the list was drawn.
      final result = await addPaperFromMetadata(
        db,
        const PaperMetadata(title: 'Layer Normalization', year: 2016),
        id: 'dup',
      );
      expect(result.id, 'dup');
      final again = await addPaperFromMetadata(
        db,
        const PaperMetadata(title: 'Layer Normalization', year: 2016),
        id: 'dup2',
      );
      expect(again.existing, isNotNull);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await close(tester);
    });

    testWidgets('offline shows one calm line with Retry', (tester) async {
      server.offline = true;
      await showSection(tester);
      await tester.tap(find.byKey(const ValueKey('citation-network-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn’t reach OpenAlex'), findsOneWidget);
      server.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Layer Normalization'), findsOneWidget);
      await close(tester);
    });

    testWidgets('paper screen shows the row only with a DOI', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(id: const Value('a'), title: 'No DOI'),
          );
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('b'),
              title: 'With DOI',
              doi: const Value('10.1000/attn'),
            ),
          );
      Future<void> open(String id) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides(),
            child: MaterialApp(home: PaperDetailScreen(paperId: id)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();
      }

      await open('a');
      expect(find.text('References · Cited by'), findsNothing);
      await close(tester);
      await open('b');
      expect(find.text('References · Cited by'), findsOneWidget);
      expect(server.requests, isEmpty);
      await close(tester);
    });
  });
}
