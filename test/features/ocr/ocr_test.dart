
import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/library_actions.dart';
import 'package:corplex/features/ocr/ocr_engine.dart';
import 'package:corplex/features/ocr/ocr_service.dart';
import 'package:corplex/features/ocr/pdf_pages.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

class FakeOcrEngine implements OcrEngine {
  final recognised = <int>[];
  Future<void> Function()? onRecognize;

  @override
  Future<OcrPageText> recognize(Uint8List png) async {
    recognised.add(png.first);
    await onRecognize?.call();
    return OcrPageText([
      OcrLine('Page ${png.first} doi 10.1234/abcd.5678', const [
        OcrWord('Page', 0.1, 0.1, 0.2, 0.15),
      ]),
    ]);
  }
}

class FakePages implements PdfPages {
  FakePages(this.texts);
  final List<String> texts;
  final rendered = <int>[];
  bool disposed = false;

  @override
  int get pageCount => texts.length;
  @override
  Future<String> text(int i) async => texts[i];
  @override
  Future<Uint8List?> renderPng(int i, {double scale = 2}) async {
    rendered.add(i);
    return Uint8List.fromList([i + 1]);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

const born =
    'Attention is all you need. The dominant sequence transduction models.';

void main() {
  late AppDatabase db;
  late FakeOcrEngine engine;
  late FakePages pages;
  late OcrService service;

  setUp(() async {
    db = AppDatabase.inMemoryForTesting();
    engine = FakeOcrEngine();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Scan',
            pdfPath: const Value('/x/scan.pdf'),
          ),
        );
    pages = FakePages(['', ' 3 ', '', '', '']);
    service = OcrService(db, engine, (_) async => pages);
  });
  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test('text-layer detection', () {
    expect(pageLacksTextLayer(''), isTrue);
    expect(pageLacksTextLayer('  12 \n'), isTrue);
    expect(pageLacksTextLayer(born), isFalse);
  });

  test('page JSON round trip and word lookup', () {
    final page = OcrPageText([
      OcrLine('Hello world', const [
        OcrWord('Hello', 0.1, 0.1, 0.3, 0.2),
        OcrWord('world', 0.35, 0.1, 0.6, 0.2),
      ]),
    ]);
    final back = OcrPageText.fromJsonString(page.toJsonString());
    expect(back.text, 'Hello world');
    expect(back.find('WOR').single.text, 'world');
    expect(
      back.wordsIn(left: 0, top: 0, right: 0.32, bottom: 1).map((w) => w.text),
      ['Hello'],
    );
    expect(OcrPageText.fromJsonString('nonsense').lines, isEmpty);
  });

  test('a page with a text layer is not recognised', () async {
    final p = FakePages([born]);
    expect(await service.recognizePage(p, 'p1', 0), isNull);
    expect(engine.recognised, isEmpty);
    expect(await db.select(db.ocrPages).get(), isEmpty);
  });

  test('queue recognises pages in order and stores them', () async {
    await service.markScanned('p1', 5);
    service.enqueue('p1');
    await Future<void>.delayed(Duration.zero);
    await service.whenIdle();
    expect(pages.rendered, [0, 1, 2, 3, 4]);
    expect(pages.disposed, isTrue);
    final stored = await (db.select(
      db.ocrPages,
    )..orderBy([(o) => OrderingTerm.asc(o.pageNumber)])).get();
    expect(stored.map((r) => r.pageNumber), [1, 2, 3, 4, 5]);
    final job = await db.select(db.ocrPapers).getSingle();
    expect(job.donePages, 5);
    expect(OcrProgress(job.pageCount, job.donePages).isDone, isTrue);
    expect((await service.storedPage('p1', 2))!.text, contains('Page 2'));
  });

  test('cancel stops after the page in progress; resume finishes', () async {
    await service.markScanned('p1', 5);
    engine.onRecognize = () async {
      if (engine.recognised.length == 2) service.cancel('p1');
    };
    service.enqueue('p1');
    await Future<void>.delayed(Duration.zero);
    await service.whenIdle();
    expect((await db.select(db.ocrPapers).getSingle()).donePages, 2);
    expect(engine.recognised, hasLength(2));

    // "Next launch": a new service picks up the unfinished paper.
    engine.onRecognize = null;
    final next = OcrService(db, engine, (_) async => pages);
    addTearDown(next.dispose);
    await next.resumePending();
    await next.whenIdle();
    expect((await db.select(db.ocrPapers).getSingle()).donePages, 5);
    // Pages already done were not recognised twice.
    expect(engine.recognised, hasLength(5));
  });

  test(
    'import: a scan is OCRed for its identifier, born-digital is not',
    () async {
      final scan = FakePages(['', '', '', '']);
      final result = await readPdfStart(
        '/x/scan.pdf',
        open: (_) async => scan,
        ocr: service,
        paperId: 'p1',
      );
      expect(result.scanned, isTrue);
      expect(result.id?.value, '10.1234/abcd.5678');
      expect(result.firstPage, contains('Page 1'));
      expect(scan.rendered, [0, 1]); // only the first two, the rest is queued
      expect((await db.select(db.ocrPapers).getSingle()).pageCount, 4);

      final digital = FakePages([born, born, '']);
      engine.recognised.clear();
      final r2 = await readPdfStart(
        '/x/d.pdf',
        open: (_) async => digital,
        ocr: service,
        paperId: 'p1',
      );
      expect(r2.scanned, isFalse);
      expect(r2.firstPage, born);
      expect(digital.rendered, isEmpty);
      expect(engine.recognised, isEmpty);
    },
  );
}
