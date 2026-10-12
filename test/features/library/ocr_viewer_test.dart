import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/library/highlights.dart';
import 'package:corplex/features/library/ocr_search.dart';
import 'package:corplex/features/library/ocr_selection.dart';
import 'package:corplex/features/library/pdf_search.dart';
import 'package:corplex/features/library/pdf_viewer_screen.dart';
import 'package:corplex/features/ocr/ocr_engine.dart';
import 'package:corplex/features/ocr/ocr_service.dart';
import 'package:corplex/features/ocr/pdf_pages.dart';

const _lineA = OcrLine('Deep residual learning', [
  OcrWord('Deep', 0.1, 0.10, 0.2, 0.13),
  OcrWord('residual', 0.22, 0.10, 0.4, 0.13),
  OcrWord('learning', 0.42, 0.10, 0.6, 0.13),
]);
const _lineB = OcrLine('for image recognition', [
  OcrWord('for', 0.1, 0.15, 0.15, 0.18),
  OcrWord('image', 0.17, 0.15, 0.3, 0.18),
  OcrWord('recognition', 0.32, 0.15, 0.6, 0.18),
]);
const _page = OcrPageText([_lineA, _lineB]);

class _Source implements PageTextSource {
  _Source(this.byPage);
  final Map<int, List<Rect>> byPage;
  @override
  int get pageCount => 3;
  @override
  Future<List<Rect>> find(int page, String query) async =>
      byPage[page] ?? const [];
}

class _NoEngine implements OcrEngine {
  @override
  Future<OcrPageText> recognize(Uint8List png) async => OcrPageText.empty;
}

class _NoPages implements PdfPages {
  @override
  int get pageCount => 0;
  @override
  Future<String> text(int index) async => '';
  @override
  Future<Uint8List?> renderPng(int index, {double scale = 2}) async => null;
  @override
  Future<void> dispose() async {}
}

void main() {
  group('search', () {
    test('findInOcr matches words and phrases', () {
      expect(findInOcr(_page, 'residual'), hasLength(1));
      expect(findInOcr(_page, 'RESID'), hasLength(1), reason: 'inside a word');
      final phrase = findInOcr(_page, 'residual learning');
      expect(phrase.single, const Rect.fromLTRB(0.22, 0.10, 0.6, 0.13));
      expect(
        findInOcr(_page, 'deep learning'),
        isEmpty,
        reason: 'not adjacent',
      );
      // Wraps onto the next line: boxed where it starts.
      expect(findInOcr(_page, 'learning for').single.top, 0.10);
      expect(findInOcr(_page, '  '), isEmpty);
    });

    test('falls back to OCR only where the text layer finds nothing', () async {
      const layer = Rect.fromLTWH(0.5, 0.5, 0.1, 0.02);
      final asked = <int>[];
      final source = OcrFallbackSource(
        _Source({
          1: [layer],
        }),
        (page) async {
          asked.add(page);
          return page == 2 ? _page : null;
        },
      );
      expect(await source.find(1, 'deep'), [layer]);
      expect(asked, isEmpty);
      expect((await source.find(2, 'image recognition')).length, 1);
      expect(await source.find(3, 'image'), isEmpty, reason: 'not read yet');
    });

    test('the count is a lower bound while reading', () async {
      var reading = true;
      final search = DocumentSearch(
        OcrFallbackSource(_Source({}), (p) async => p == 1 ? _page : null),
        incomplete: () => reading,
      );
      await search.search('image');
      expect(search.summary, '1 of 1+');
      await search.search('zzz');
      expect(search.summary, 'No matches yet');
      reading = false;
      expect(search.summary, 'No matches');
      search.dispose();
    });
  });

  group('selection', () {
    final words = _page.words.toList();

    test('selects in reading order whichever way the drag goes', () {
      final forward = selectOcrWords(
        words,
        const Offset(0.25, 0.11),
        const Offset(0.2, 0.16),
      );
      expect(ocrQuote(forward), 'residual learning for image');
      final backward = selectOcrWords(
        words,
        const Offset(0.2, 0.16),
        const Offset(0.25, 0.11),
      );
      expect(ocrQuote(backward), ocrQuote(forward));
      // Off the text snaps to the nearest word.
      expect(
        ocrQuote(
          selectOcrWords(words, const Offset(0, 0), const Offset(0.5, 0.0)),
        ),
        'Deep residual learning',
      );
    });

    test('one box per line', () {
      final rects = ocrRects(words.sublist(1, 5));
      expect(rects, hasLength(2));
      expect(rects.first, const Rect.fromLTRB(0.22, 0.10, 0.6, 0.13));
      expect(rects.last.left, 0.1);
      expect(rects.last.right, 0.3);
    });

    test('creates an ordinary highlight row', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      final h = await createOcrHighlight(
        db,
        paperId: 'p',
        page: 4,
        words: words.sublist(0, 4),
        color: const Color(0xFFFFF59D),
      );
      expect(h.quote, 'Deep residual learning for');
      expect(h.pageNumber, 4);
      expect(decodeRects(h.rectsJson), hasLength(2));
      expect(await db.select(db.highlights).get(), hasLength(1));
    });

    testWidgets('long-press and drag, then Highlight', (tester) async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      await db
          .into(db.ocrPages)
          .insert(
            OcrPagesCompanion.insert(
              paperId: 'p',
              pageNumber: 1,
              content: Value(_page.text),
              wordsJson: Value(_page.toJsonString()),
            ),
          );
      final chosen = <(OcrSelectionAction, String)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: PageOverlay(
                  paperId: 'p',
                  pageNumber: 1,
                  pageRect: const Rect.fromLTWH(0, 0, 400, 500),
                  inkMode: false,
                  color: Colors.yellow,
                  onOcrSelection: (a, w, _) => chosen.add((a, ocrQuote(w))),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(PageOverlay));
      final gesture = await tester.startGesture(origin + const Offset(100, 55));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(origin + const Offset(80, 83));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Highlight'), findsOneWidget);
      expect(find.text('Quote to note'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Highlight'));
      await tester.pumpAndSettle();
      expect(chosen, [
        (OcrSelectionAction.highlight, 'residual learning for image'),
      ]);

      // A quick drag is not a selection.
      final quick = await tester.startGesture(origin + const Offset(100, 55));
      await quick.moveTo(origin + const Offset(160, 83));
      await quick.up();
      await tester.pumpAndSettle();
      expect(find.text('Highlight'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('viewer', () {
    Future<(AppDatabase, ProviderContainer)> open(
      WidgetTester tester, {
      required String pageText,
      bool scanned = false,
    }) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 't'));
      if (scanned) {
        await db
            .into(db.ocrPapers)
            .insert(
              OcrPapersCompanion.insert(
                paperId: 'p',
                pageCount: 4,
                donePages: const Value(1),
              ),
            );
      }
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ocrEngineProvider.overrideWithValue(_NoEngine()),
          pdfPagesOpenerProvider.overrideWithValue((_) async => _NoPages()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PdfViewerScreen(
              paperId: 'p',
              pdfPath: '/none.pdf',
              viewerBuilder: (context, controller, params) =>
                  const SizedBox.expand(),
              textProbe: PageTextProbe(
                pageCount: 4,
                text: (_) async => pageText,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (db, container);
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('Recognise text appears for a page without text', (
      tester,
    ) async {
      final (db, container) = await open(tester, pageText: '');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Recognise text'), findsOneWidget);
      await tester.tap(find.text('Recognise text'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container.read(ocrServiceProvider).whenIdle(),
      );
      final row = await tester.runAsync(
        () => db.select(db.ocrPapers).getSingle(),
      );
      expect(row!.pageCount, 4);
      await dispose(tester);
    });

    testWidgets('not offered when the page has text', (tester) async {
      await open(
        tester,
        pageText: 'A page with plenty of real text on it, certainly.',
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Recognise text'), findsNothing);
      await dispose(tester);
    });

    testWidgets('not offered once the paper is marked scanned', (tester) async {
      await open(tester, pageText: '', scanned: true);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Recognise text'), findsNothing);
      await dispose(tester);
    });

    testWidgets('quiet progress while reading, nothing after', (tester) async {
      final (db, _) = await open(tester, pageText: '', scanned: true);
      expect(find.text('Reading text… 25%'), findsOneWidget);
      await (db.update(db.ocrPapers))
          .write(const OcrPapersCompanion(donePages: Value(4)));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ocr-progress')), findsNothing);
      await dispose(tester);
    });
  });
}
