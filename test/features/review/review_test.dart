import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/review/review_prompt.dart';
import 'package:corplex/features/review/review_schedule.dart';
import 'package:corplex/features/review/review_screen.dart';

void main() {
  final now = DateTime(2026, 10, 10, 9);

  Highlight highlight(String id, DateTime created) => Highlight(
    id: id,
    paperId: 'p',
    pageNumber: 1,
    quote: 'q',
    rectsJson: '[]',
    colorHex: '#fff',
    createdAt: created,
    updatedAt: created,
  );

  group('scheduling', () {
    test('keeping walks 1, 3, 7, 14, 30, 90 and then stays at 90', () {
      ReviewEntry? e;
      final days = <int>[];
      for (var i = 0; i < 8; i++) {
        e = keepEntry(e, now);
        days.add(e.due.difference(now).inDays);
      }
      expect(days, [1, 3, 7, 14, 30, 90, 90, 90]);
    });

    test('skipping asks tomorrow without counting as a review', () {
      final kept = keepEntry(keepEntry(null, now), now);
      final skipped = skipEntry(kept, now);
      expect(skipped.keeps, kept.keeps);
      expect(skipped.due, now.add(const Duration(days: 1)));
    });

    test('never-reviewed highlights are due a day after creation', () {
      final fresh = highlight('a', now.subtract(const Duration(hours: 3)));
      final old = highlight('b', now.subtract(const Duration(days: 2)));
      final all = [
        (highlight: fresh, paper: _paper),
        (highlight: old, paper: _paper),
      ];
      expect(dueHighlights(all, {}, now).map((e) => e.highlight.id), ['b']);
    });

    test('a scheduled highlight waits for its date; overdue first', () {
      final a = highlight('a', now.subtract(const Duration(days: 30)));
      final b = highlight('b', now.subtract(const Duration(days: 30)));
      final c = highlight('c', now.subtract(const Duration(days: 30)));
      final schedule = {
        'a': ReviewEntry(keeps: 1, due: now.add(const Duration(days: 2))),
        'b': ReviewEntry(keeps: 1, due: now.subtract(const Duration(hours: 1))),
      };
      final all = [
        for (final h in [a, b, c]) (highlight: h, paper: _paper),
      ];
      expect(dueHighlights(all, schedule, now).map((e) => e.highlight.id), [
        'c',
        'b',
      ]);
    });

    test('pruning drops deleted highlights', () {
      final e = ReviewEntry(keeps: 1, due: now);
      expect(pruneSchedule({'a': e, 'b': e}, {'b'}).keys, ['b']);
    });
  });

  group('prompt', () {
    late AppDatabase db;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 'Paper'));
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              paperId: 'p',
              pageNumber: 2,
              quote: 'A passage worth keeping',
              rectsJson: '[]',
              createdAt: Value(now.subtract(const Duration(days: 3))),
            ),
          );
    });
    tearDown(() => db.close());

    Future<void> show(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            reviewClockProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders nothing unless opted in', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await show(tester, const ReviewPrompt());
      expect(find.textContaining('to revisit'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('shows when opted in and due, and can be dismissed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'review.prompt': true});
      await show(tester, const ReviewPrompt());
      expect(find.text('1 highlight to revisit'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.textContaining('to revisit'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('hidden when nothing is due', (tester) async {
      SharedPreferences.setMockInitialValues({
        'review.prompt': true,
        'review.schedule':
            '{"x":{"k":1,"d":${now.add(const Duration(days: 5)).millisecondsSinceEpoch}}}',
      });
      await db.delete(db.highlights).go();
      await show(tester, const ReviewPrompt());
      expect(find.textContaining('to revisit'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('the review screen keeps a highlight and moves on', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await show(tester, const ReviewScreen());
      expect(find.textContaining('A passage worth keeping'), findsOneWidget);
      expect(find.text('Open in paper'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('All caught up'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ReviewScreen)),
      );
      final schedule = container.read(reviewSettingsProvider).schedule;
      expect(schedule, hasLength(1));
      expect(schedule.values.single.due, now.add(const Duration(days: 1)));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(container.read(reviewSettingsProvider).remind, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

final _paper = Paper(
  id: 'p',
  title: 'Paper',
  authors: '',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
