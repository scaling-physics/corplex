import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/pdf_search.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';

/// Pages 1..3 hold "alpha" 2, 0 and 1 times.
class _FakeSource implements PageTextSource {
  final queries = <String>[];
  @override
  int get pageCount => 3;
  @override
  Future<List<Rect>> find(int page, String query) async {
    queries.add(query);
    if (query.toLowerCase() != 'alpha') return const [];
    const r = Rect.fromLTWH(0.1, 0.1, 0.2, 0.02);
    return switch (page) {
      1 => [r, r.shift(const Offset(0, 0.2))],
      3 => [r],
      _ => const [],
    };
  }
}

void main() {
  group('DocumentSearch', () {
    test('counts, wraps and reveals', () async {
      final search = DocumentSearch(_FakeSource());
      final revealed = <SearchMatch>[];
      search.onReveal = revealed.add;
      await search.search('Alpha');
      expect(search.matches.length, 3);
      expect(search.summary, '1 of 3');
      expect(revealed.single.page, 1, reason: 'first match revealed');
      search.next();
      search.next();
      expect(search.summary, '3 of 3');
      expect(revealed.last.page, 3);
      search.next();
      expect(search.summary, '1 of 3', reason: 'wraps forward');
      search.previous();
      expect(search.summary, '3 of 3', reason: 'wraps backward');
      expect(search.indicesOnPage(1), [0, 1]);
      expect(search.indicesOnPage(2), isEmpty);
      await search.search('zzz');
      expect(search.summary, 'No matches');
      await search.search('');
      expect(search.summary, '');
      search.dispose();
    });

    test('a newer query supersedes an older one', () async {
      final search = DocumentSearch(_FakeSource());
      final first = search.search('alpha');
      await search.search('beta');
      await first;
      expect(search.matches, isEmpty);
      search.dispose();
    });
  });

  group('viewer', () {
    Future<List<SearchMatch>> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      final revealed = <SearchMatch>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: PdfViewerScreen(
              paperId: 'p',
              pdfPath: '/none.pdf',
              viewerBuilder: (context, controller, params) =>
                  const SizedBox.expand(),
              searchSourceBuilder: (_) => _FakeSource(),
              onSearchReveal: revealed.add,
            ),
          ),
        ),
      );
      await tester.pump();
      return revealed;
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    String count(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('find-count'))).data!;

    testWidgets('opens, searches, steps, wraps and closes', (tester) async {
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
      final revealed = await open(tester);
      expect(find.byKey(const ValueKey('find-field')), findsNothing);

      await tester.tap(find.byTooltip('Find in document'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-field')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('find-field')), 'alpha');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(count(tester), '1 of 3');
      expect(revealed.length, 1);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(count(tester), '2 of 3');
      expect(revealed.length, 2);
      await tester.tap(find.byTooltip('Previous match'));
      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(count(tester), '3 of 3', reason: 'wraps');

      // Enter and Shift+Enter.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(count(tester), '1 of 3');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(count(tester), '3 of 3');

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-field')), findsNothing);
      expect(find.byTooltip('Find in document'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('Cmd+F opens the field', (tester) async {
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
      await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-field')), findsOneWidget);
      await dispose(tester);
    });
  });
}
