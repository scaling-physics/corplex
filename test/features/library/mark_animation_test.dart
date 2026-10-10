import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/flight.dart';
import 'package:corplex/features/library/highlight_sweep.dart';
import 'package:corplex/features/library/highlights.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/settings/appearance_settings.dart';
import 'package:corplex/theme/app_theme.dart';

bool _isSweep(Widget w) =>
    w is CustomPaint && w.painter.runtimeType.toString() == '_SweepPainter';

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('colour matrix', () {
    test('lerps every value, exactly at the ends', () {
      final a = ReadingTheme.paper.matrix;
      final b = ReadingTheme.night.matrix;
      expect(lerpColorMatrix(a, b, 0), a);
      expect(lerpColorMatrix(a, b, 1), b);
      final mid = lerpColorMatrix(a, b, 0.5);
      for (var i = 0; i < 20; i++) {
        expect(mid[i], closeTo((a[i] + b[i]) / 2, 1e-9));
      }
    });
  });

  group('sweep timing', () {
    test('every line is empty at 0 and full at 1', () {
      for (final n in [1, 2, 7]) {
        for (var i = 0; i < n; i++) {
          expect(sweepLineProgress(0, i, n), 0);
          expect(sweepLineProgress(1, i, n), 1);
        }
      }
    });

    test('lines are staggered: earlier lines are further along', () {
      expect(
        sweepLineProgress(0.3, 0, 4),
        greaterThan(sweepLineProgress(0.3, 3, 4)),
      );
    });

    test('fresh highlights are claimed once', () {
      final f = FreshHighlights()..add('a');
      expect(f.claim('a'), isTrue);
      expect(f.claim('a'), isFalse);
      expect(f.claim('never'), isFalse);
    });
  });

  group('page overlay', () {
    late AppDatabase db;
    late FreshHighlights fresh;

    setUp(() async {
      db = AppDatabase.inMemoryForTesting();
      fresh = FreshHighlights();
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 'T'));
    });

    tearDown(() async {
      fresh.dispose();
      await db.close();
    });

    Future<String> add() => addHighlight(
      db,
      paperId: 'p',
      pageNumber: 1,
      quote: 'some words',
      rects: [
        const Rect.fromLTWH(0.1, 0.1, 0.5, 0.02),
        const Rect.fromLTWH(0.1, 0.13, 0.3, 0.02),
      ],
      color: highlightInks.first,
    );

    Future<void> pumpOverlay(
      WidgetTester tester, {
      bool reduced = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            freshHighlightsProvider.overrideWithValue(fresh),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: const Scaffold(
              body: PageOverlay(
                paperId: 'p',
                pageNumber: 1,
                pageRect: Rect.fromLTWH(0, 0, 400, 600),
                inkMode: false,
                color: Color(0xFFFFEB3B),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a new highlight sweeps in, then settles', (tester) async {
      await pumpOverlay(tester);
      await tester.runAsync(() async {
        fresh.add(await add());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byWidgetPredicate(_isSweep), findsOneWidget);

      await tester.pump(AppMotion.long);
      await tester.pump(AppMotion.long);
      expect(find.byWidgetPredicate(_isSweep), findsNothing);
      await _disposeTree(tester);
    });

    testWidgets('existing highlights appear without a sweep', (tester) async {
      await tester.runAsync(add);
      await pumpOverlay(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byWidgetPredicate(_isSweep), findsNothing);
      await _disposeTree(tester);
    });

    testWidgets('reduced motion skips the sweep', (tester) async {
      await pumpOverlay(tester, reduced: true);
      await tester.runAsync(() async {
        fresh.add(await add());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byWidgetPredicate(_isSweep), findsNothing);
      await _disposeTree(tester);
    });
  });

  group('reading filter', () {
    Widget host(ReadingTheme t) => MaterialApp(
      home: ReadingFilter(theme: t, child: const SizedBox.expand()),
    );

    ColorFilter current(WidgetTester tester) =>
        tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter;

    testWidgets('tweens to the new theme instead of snapping', (tester) async {
      await tester.pumpWidget(host(ReadingTheme.paper));
      await tester.pumpWidget(host(ReadingTheme.night));
      await tester.pump(AppMotion.medium ~/ 2);
      expect(current(tester), isNot(ReadingTheme.night.filter));
      expect(current(tester), isNot(ReadingTheme.paper.filter));
      await tester.pump(AppMotion.medium);
      expect(current(tester), ReadingTheme.night.filter);
    });
  });

  group('flight', () {
    Widget host(void Function(BuildContext) onReady, {bool reduced = false}) =>
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => onReady(context),
              );
              return const Scaffold();
            },
          ),
        );

    testWidgets('the card is in the overlay until it lands', (tester) async {
      var landed = false;
      await tester.pumpWidget(
        host((context) {
          flyAcross(
            context,
            from: const Offset(100, 100),
            to: const Rect.fromLTWH(500, 400, 120, 48),
            size: QuoteCard.size,
            child: const QuoteCard(quote: 'a passage'),
          ).then((_) => landed = true);
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(QuoteCard), findsOneWidget);
      expect(landed, isFalse);

      await tester.pump(AppMotion.long);
      await tester.pump();
      expect(find.byType(QuoteCard), findsNothing);
      expect(landed, isTrue);
    });

    testWidgets('reduced motion shows no flight', (tester) async {
      await tester.pumpWidget(
        host((context) {
          flyAcross(
            context,
            from: const Offset(100, 100),
            to: const Rect.fromLTWH(500, 400, 120, 48),
            size: QuoteCard.size,
            child: const QuoteCard(quote: 'a passage'),
          );
        }, reduced: true),
      );
      await tester.pump();
      expect(find.byType(QuoteCard), findsNothing);
    });
  });
}
