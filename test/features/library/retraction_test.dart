import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:corplex/features/library/metadata_lookup.dart';
import 'package:corplex/features/library/retraction.dart';
import 'package:corplex/features/library/retraction_notice.dart';

const _doi = '10.1016/s0140-6736(97)11096-0';

/// A real Crossref answer for the retracted Wakefield paper (a retraction
/// and a later "correction"-typed commentary).
String _fixture() =>
    File('test/features/library/retraction_crossref_fixture.json')
        .readAsStringSync();

class _Clock {
  DateTime t = DateTime(2026, 10, 18);
  DateTime call() => t;
}

void main() {
  group('parsing', () {
    test('retraction and correction from a real response', () {
      final n = parseUpdateNotices(
        jsonDecode(_fixture()) as Map<String, dynamic>,
        _doi,
      );
      expect(n.map((e) => e.kind), [
        NoticeKind.retraction,
        NoticeKind.correction,
      ]);
      expect(n.first.noticeDoi, '10.1016/s0140-6736(10)60175-4');
      expect(n.first.date, DateTime.utc(2010, 2, 6));
      expect(n.first.message, 'Retracted on 6 February 2010 — see the notice');
      expect(
        n.first.link.toString(),
        'https://doi.org/10.1016/s0140-6736(10)60175-4',
      );
      expect(n.last.message, startsWith('Corrected on 6 March 2004'));
    });

    test('other DOIs, unknown types and empty answers are ignored', () {
      final json = {
        'message': {
          'items': [
            {
              'DOI': '10.1/a',
              'update-to': [
                {'DOI': '10.1/other', 'type': 'retraction'},
                {'DOI': '10.1/TARGET', 'type': 'new_version'},
                {'DOI': '10.1/target', 'type': 'expression_of_concern'},
              ],
              'issued': {
                'date-parts': [
                  [2020],
                ],
              },
            },
            {'DOI': '10.1/b', 'update-to': 'junk'},
          ],
        },
      };
      final n = parseUpdateNotices(json, '10.1/target');
      expect(n, hasLength(1));
      expect(n.single.kind, NoticeKind.expressionOfConcern);
      expect(
        n.single.message,
        'Expression of concern issued on 1 January 2020 — see the notice',
      );
      expect(
        parseUpdateNotices({
          'message': {'items': []},
        }, _doi),
        isEmpty,
      );
      expect(parseUpdateNotices({}, _doi), isEmpty);
    });

    test('a notice without a date reads plainly', () {
      const n = UpdateNotice(kind: NoticeKind.retraction, noticeDoi: '10.1/x');
      expect(n.message, 'Retracted — see the notice');
    });
  });

  group('service and cache', () {
    late Directory dir;
    late _Clock clock;
    late int calls;
    late bool online;
    late RetractionService service;
    late Uri lastUrl;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('retr');
      clock = _Clock();
      calls = 0;
      online = true;
      service = RetractionService(
        RetractionClient(
          client: MockClient((req) async {
            calls++;
            lastUrl = req.url;
            if (!online) throw const SocketException('offline');
            return http.Response(_fixture(), 200);
          }),
        ),
        RetractionCache(() async => dir, now: clock.call),
      );
    });
    tearDown(() => dir.delete(recursive: true));

    test('asks Crossref over https with the updates filter', () async {
      final n = await service.check(_doi);
      expect(n, hasLength(2));
      expect(lastUrl.scheme, 'https');
      expect(lastUrl.queryParameters['filter'], 'updates:$_doi');
      expect(lastUrl.queryParameters.containsKey('mailto'), isFalse);
    });

    test('fresh cache is used, 30 days later it is asked again', () async {
      await service.check(_doi);
      await service.check(_doi.toUpperCase());
      expect(calls, 1);
      clock.t = clock.t.add(const Duration(days: 29));
      await service.check(_doi);
      expect(calls, 1);
      clock.t = clock.t.add(const Duration(days: 2));
      await service.check(_doi);
      expect(calls, 2);
    });

    test('offline: a stale copy is used, nothing cached is unknown', () async {
      expect(await service.check(_doi), hasLength(2));
      clock.t = clock.t.add(const Duration(days: 90));
      online = false;
      expect((await service.check(_doi))!.first.kind, NoticeKind.retraction);
      expect(await service.check('10.1000/never-seen'), isNull);
      expect(await service.cached(_doi), hasLength(2));
      expect(await service.cached('10.1000/never-seen'), isEmpty);
    });

    test('no cache folder means no network at all', () async {
      final none = RetractionService(
        RetractionClient(
          client: MockClient((_) async {
            calls++;
            return http.Response(_fixture(), 200);
          }),
        ),
        RetractionCache(() async => throw StateError('no plugin')),
      );
      expect(await none.check(_doi), isNull);
      expect(calls, 0);
    });

    test('a paper with no notices is cached as empty', () async {
      final quiet = RetractionService(
        RetractionClient(
          client: MockClient(
            (_) async => http.Response('{"message":{"items":[]}}', 200),
          ),
        ),
        RetractionCache(() async => dir, now: clock.call),
      );
      expect(await quiet.check('10.1000/fine'), isEmpty);
      expect(await quiet.cached('10.1000/fine'), isEmpty);
    });

    test('a bad status throws LookupFailed from the client', () {
      final bad = RetractionClient(
        client: MockClient((_) async => http.Response('', 503)),
      );
      expect(() => bad.notices(_doi), throwsA(isA<LookupFailed>()));
    });
  });

  group('widgets', () {
    const retraction = UpdateNotice(
      kind: NoticeKind.retraction,
      noticeDoi: '10.1/r',
    );
    final retractionDated = UpdateNotice(
      kind: NoticeKind.retraction,
      noticeDoi: '10.1/r',
      date: DateTime.utc(2024, 3, 12),
    );
    const correction = UpdateNotice(
      kind: NoticeKind.correction,
      noticeDoi: '10.1/c',
    );

    Future<void> pump(
      WidgetTester tester,
      Widget child,
      List<UpdateNotice>? notices,
    ) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          noticeCheckProvider.overrideWith((ref, doi) async => notices),
          cachedNoticesProvider.overrideWith(
            (ref, doi) async => notices ?? const [],
          ),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

    testWidgets('paper screen notice: retraction in the error tone', (
      tester,
    ) async {
      await pump(tester, const RetractionNotice(doi: '10.1/x'), [
        retractionDated,
        correction,
      ]);
      await tester.pump();
      expect(
        find.text('Retracted on 12 March 2024 — see the notice'),
        findsOneWidget,
      );
      expect(find.text('Corrected — see the notice'), findsOneWidget);
      final scheme = Theme.of(tester.element(find.byType(RetractionNotice)))
          .colorScheme;
      Color? colorOf(String text) => tester
          .widget<Material>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Material))
                .first,
          )
          .color;
      expect(
        colorOf('Retracted on 12 March 2024 — see the notice'),
        scheme.errorContainer,
      );
      expect(
        colorOf('Corrected — see the notice'),
        isNot(scheme.errorContainer),
      );
    });

    testWidgets('nothing at all without notices', (tester) async {
      await pump(tester, const RetractionNotice(doi: '10.1/x'), const []);
      await tester.pump();
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(find.textContaining('see the notice'), findsNothing);
    });

    for (final (label, doi, notices, shown) in [
      ('a retraction', '10.1/x', [retraction], true),
      ('only a correction', '10.1/x', [correction], false),
      ('no DOI', null, [retraction], false),
    ]) {
      testWidgets('library marker: $label', (tester) async {
        await pump(tester, RetractionMarker(doi: doi), notices);
        await tester.pump();
        expect(
          find.byIcon(Icons.warning_amber_rounded),
          shown ? findsOneWidget : findsNothing,
        );
      });
    }
  });
}
