import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/library/reading_progress.dart';
import 'package:corplex/features/library/viewer_navigation.dart';

Paper _paper({int? lastPage, int? pageCount, ReadingStatus? status}) => Paper(
  id: 'p',
  title: 't',
  authors: '',
  lastPage: lastPage,
  pageCount: pageCount,
  readingStatus: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('reading progress', () {
    test('only for started, unfinished papers with a known page count', () {
      expect(readingProgress(_paper(lastPage: 5)), isNull, reason: 'no count');
      expect(readingProgress(_paper(pageCount: 10)), isNull, reason: 'new');
      expect(readingProgress(_paper(lastPage: 1, pageCount: 10)), isNull);
      expect(readingProgress(_paper(lastPage: 5, pageCount: 10)), 0.5);
      expect(
        readingProgress(_paper(pageCount: 10, status: ReadingStatus.reading)),
        0.1,
      );
      expect(
        readingProgress(
          _paper(lastPage: 10, pageCount: 10, status: ReadingStatus.done),
        ),
        isNull,
        reason: 'finished papers stay quiet',
      );
      expect(readingProgress(_paper(lastPage: 99, pageCount: 10)), 1.0);
    });

    testWidgets('bar appears only when there is progress', (tester) async {
      Future<void> show(Paper p) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReadingProgressBar(paper: p)),
        ),
      );
      await show(_paper(lastPage: 1, pageCount: 10));
      expect(find.byKey(const ValueKey('reading-progress')), findsNothing);
      await show(_paper(lastPage: 5, pageCount: 10));
      await tester.pumpAndSettle();
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('reading-progress')),
      );
      expect(bar.value, closeTo(0.5, 1e-6));
    });

    test('page count is saved on load only when it changed', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      Future<int> dirty() async =>
          (await db
                  .customSelect(
                    "SELECT COUNT(*) c FROM sync_dirty WHERE table_name = 'papers'",
                  )
                  .getSingle())
              .read<int>('c');
      await savePageCountIfChanged(db, 'p', 30);
      expect((await db.select(db.papers).getSingle()).pageCount, 30);
      await db.customStatement('DELETE FROM sync_dirty');
      await savePageCountIfChanged(db, 'p', 30);
      expect(await dirty(), 0, reason: 'unchanged: not an edit');
      await savePageCountIfChanged(db, 'p', 0);
      expect((await db.select(db.papers).getSingle()).pageCount, 30);
      await savePageCountIfChanged(db, 'p', 31);
      expect((await db.select(db.papers).getSingle()).pageCount, 31);
    });
  });

  group('page strip', () {
    testWidgets('shows dots for highlighted pages and jumps on tap', (
      tester,
    ) async {
      final jumped = <int>[];
      final current = ValueNotifier(2);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PageStrip(
                pageCount: 20,
                current: current,
                marks: const [
                  (page: 2, y: 0.1, color: Colors.amber),
                  (page: 2, y: 0.5, color: Colors.amber),
                  (page: 3, y: 0.5, color: Colors.green),
                ],
                onJump: jumped.add,
                thumbnail: (_, page) => Text('thumb$page'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('strip-dot')), findsNWidgets(2));
      // Lazy: far pages are not built.
      expect(find.text('thumb20'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('strip-page-3')));
      expect(jumped, [3]);
      current.value = 14; // scrolling the document follows along
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('strip-page-14')), findsOneWidget);
    });
  });

  group('minimap', () {
    testWidgets('ticks sit at their place in the document and tap jumps', (
      tester,
    ) async {
      final jumped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: HighlightMinimap(
                pageCount: 10,
                marks: const [
                  (page: 1, y: 0.0, color: Colors.amber),
                  (page: 6, y: 0.0, color: Colors.green),
                ],
                onJump: jumped.add,
              ),
            ),
          ),
        ),
      );
      final first = tester.getCenter(
        find.byKey(const ValueKey('minimap-tick-1-0')),
      );
      final sixth = tester.getCenter(
        find.byKey(const ValueKey('minimap-tick-6-198')),
      );
      // Page 6 starts half way down the document.
      expect((sixth.dy - first.dy), closeTo(198, 1));
      await tester.tap(find.byKey(const ValueKey('minimap-tick-6-198')));
      expect(jumped, [6]);
    });

    testWidgets('empty space does not take touches', (tester) async {
      var below = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GestureDetector(onTap: () => below++),
                Positioned.fill(
                  child: HighlightMinimap(
                    pageCount: 10,
                    marks: const [(page: 1, y: 0.0, color: Colors.amber)],
                    onJump: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(400, 300));
      expect(below, 1);
    });

    testWidgets('absent without highlights', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HighlightMinimap(pageCount: 5, marks: const [], onJump: (_) {}),
        ),
      );
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('focus mode', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
              calls.add(call.arguments as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<PdfViewerParams> open(
      WidgetTester tester, {
      required Size size,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      late PdfViewerParams captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: PdfViewerScreen(
              paperId: 'p',
              pdfPath: '/none.pdf',
              viewerBuilder: (context, controller, params) {
                captured = params;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return captured;
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    PdfViewerGeneralTapHandlerDetails tap({
      PdfViewerPart on = PdfViewerPart.background,
    }) => PdfViewerGeneralTapHandlerDetails(
      localPosition: Offset.zero,
      documentPosition: Offset.zero,
      type: PdfViewerGeneralTapType.tap,
      tapOn: on,
    );

    testWidgets('a tap on bare page hides the chrome, another restores it', (
      tester,
    ) async {
      final params = await open(tester, size: const Size(390, 800));
      expect(find.byType(AppBar), findsOneWidget);
      final context = tester.element(find.byType(Scaffold));
      final controller = PdfViewerController();

      params.onGeneralTap!(context, controller, tap());
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(calls, contains('SystemUiMode.immersiveSticky'));

      // A fresh params object is built on rebuild; use the latest handler.
      params.onGeneralTap!(context, controller, tap());
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(calls.last, 'SystemUiMode.edgeToEdge');
      await dispose(tester);
    });

    testWidgets('taps on a selection are left alone', (tester) async {
      final params = await open(tester, size: const Size(390, 800));
      final context = tester.element(find.byType(Scaffold));
      params.onGeneralTap!(
        context,
        PdfViewerController(),
        tap(on: PdfViewerPart.selectedText),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('leaving while focused restores the system bars', (
      tester,
    ) async {
      final params = await open(tester, size: const Size(390, 800));
      final context = tester.element(find.byType(Scaffold));
      params.onGeneralTap!(context, PdfViewerController(), tap());
      await tester.pumpAndSettle();
      calls.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(calls, ['SystemUiMode.edgeToEdge']);
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('tablets keep the system bars', (tester) async {
      final params = await open(tester, size: const Size(1000, 800));
      final context = tester.element(find.byType(Scaffold));
      params.onGeneralTap!(context, PdfViewerController(), tap());
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(calls, isEmpty);
      await dispose(tester);
    });
  });
}
