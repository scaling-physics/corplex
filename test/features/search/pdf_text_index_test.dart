
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/notes/note_table.dart';
import 'package:corplex/features/ocr/pdf_pages.dart';
import 'package:corplex/features/search/pdf_text_index.dart';
import 'package:corplex/features/search/search_index.dart';

class FakePages implements PdfPages {
  FakePages(this.texts);
  final List<String> texts;
  int disposed = 0;

  @override
  int get pageCount => texts.length;
  @override
  Future<String> text(int index) async => texts[index];
  @override
  Future<Uint8List?> renderPng(int index, {double scale = 2}) async => null;
  @override
  Future<void> dispose() async => disposed++;
}

const _filler = 'Lorem ipsum dolor sit amet consectetur adipiscing elit. ';

void main() {
  late AppDatabase db;
  late Map<String, List<String>> files;
  late Map<String, String> stamps;
  late PdfTextIndex index;

  Future<void> addPaper(String id, String title, String? path) => db
      .into(db.papers)
      .insert(
        PapersCompanion.insert(
          id: Value(id),
          title: title,
          pdfPath: Value(path),
        ),
      );

  setUp(() {
    db = AppDatabase.inMemoryForTesting();
    files = {};
    stamps = {};
    index = PdfTextIndex(
      db,
      (path) async => FakePages(files[path]!),
      stamper: (path) async => stamps[path] ?? 'v1',
    );
  });
  tearDown(() => db.close());

  test('indexes pages and finds them with page and snippet', () async {
    files['/a.pdf'] = [
      '$_filler Hippocampal replay supports memory consolidation. $_filler',
      '$_filler nothing relevant here at all. $_filler',
      '$_filler replay again, hippocampal replay during sleep. $_filler',
    ];
    await addPaper('p1', 'Replay paper', '/a.pdf');
    await index.run();

    final hits = await index.search('hippocampal replay');
    expect(hits.map((h) => h.page).toSet(), {1, 3});
    expect(hits.every((h) => h.kind == SearchKind.pdfText), isTrue);
    expect(hits.first.title, 'Replay paper');
    expect(hits.first.paperId, 'p1');
    expect(hits.first.snippet, contains('⟦'));
    expect(await index.incomplete, isFalse);
  });

  test('caps matches per paper and groups by paper', () async {
    files['/a.pdf'] = [for (var i = 0; i < 6; i++) 'engram cells page $i'];
    files['/b.pdf'] = ['engram once'];
    await addPaper('p1', 'A', '/a.pdf');
    await addPaper('p2', 'B', '/b.pdf');
    await index.run();
    final hits = await index.search('engram');
    expect(hits.where((h) => h.paperId == 'p1'), hasLength(3));
    expect(hits.where((h) => h.paperId == 'p2'), hasLength(1));
    // Grouped: p1's hits are contiguous.
    final ids = hits.map((h) => h.paperId).toList();
    expect(ids.join(), anyOf('p1p1p1p2', 'p2p1p1p1'));
  });

  test('scanned pages fall back to OCR text', () async {
    files['/scan.pdf'] = ['', ''];
    await addPaper('p1', 'Scan', '/scan.pdf');
    await db
        .into(db.ocrPages)
        .insert(
          OcrPagesCompanion.insert(
            paperId: 'p1',
            pageNumber: 2,
            content: const Value('Dentate gyrus pattern separation recognised'),
          ),
        );
    await db
        .into(db.ocrPapers)
        .insert(OcrPapersCompanion.insert(paperId: 'p1', pageCount: 2));
    await index.run();
    // Page 1 isn't recognised yet and OCR is running: indexing waits.
    expect(await index.incomplete, isTrue);
    expect(await index.search('dentate'), isEmpty);

    await db
        .into(db.ocrPages)
        .insert(
          OcrPagesCompanion.insert(
            paperId: 'p1',
            pageNumber: 1,
            content: const Value('Cerebellum granule cells recognised'),
          ),
        );
    await index.run();
    expect(await index.incomplete, isFalse);
    expect((await index.search('dentate')).single.page, 2);
    expect((await index.search('cerebellum')).single.page, 1);
  });

  test('deleting a paper drops its rows', () async {
    files['/a.pdf'] = ['unique zebrafish word'];
    await addPaper('p1', 'A', '/a.pdf');
    await index.run();
    expect(await index.search('zebrafish'), hasLength(1));
    await (db.delete(db.papers)..where((p) => p.id.equals('p1'))).go();
    expect(await index.search('zebrafish'), isEmpty);
    await index.run();
    final left = await db
        .customSelect('SELECT COUNT(*) c FROM pdf_pages_index')
        .getSingle();
    expect(left.read<int>('c'), 0);
  });

  test('a changed PDF is indexed again, an unchanged one is not', () async {
    files['/a.pdf'] = ['alpha beta'];
    await addPaper('p1', 'A', '/a.pdf');
    await index.run();
    expect(await index.search('alpha'), hasLength(1));

    files['/a.pdf'] = ['gamma delta'];
    await index.run(); // same stamp: untouched
    expect(await index.search('gamma'), isEmpty);

    stamps['/a.pdf'] = 'v2';
    await index.run();
    expect(await index.search('alpha'), isEmpty);
    expect(await index.search('gamma'), hasLength(1));
  });

  test('a 300-page paper indexes and yields', () async {
    files['/big.pdf'] = [
      for (var i = 0; i < 300; i++) '$_filler page $i token$i $_filler',
    ];
    await addPaper('p1', 'Big', '/big.pdf');
    var ticks = 0;
    final ticker = Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      ticks++;
      return await index.incomplete;
    });
    await index.run();
    await ticker;
    expect(ticks, greaterThan(1));
    expect((await index.search('token299')).single.page, 300);
  });

  group('note text', () {
    Future<void> addNote(String id, String content) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: const Value('Untitled'),
            content: Value(content),
          ),
        );

    test('handwriting and table cells make a note findable', () async {
      final sketch = const Sketch().copyWith(text: 'quokka handwriting');
      final table = NoteTable(
        rows: [
          ['Gene', 'Effect'],
          ['arc', 'plasticity wombat'],
        ],
      );
      final content =
          '[{"insert":"body\\n"},'
          '{"insert":{"sketch":${_q(sketch.encode())}}},'
          '{"insert":"\\n"},'
          '{"insert":{"table":${_q(table.encode())}}},'
          '{"insert":"\\n"}]';
      await addNote('n1', content);
      final search = SearchIndex(db);
      expect((await search.search('quokka')).single.id, 'n1');
      expect((await search.search('wombat')).single.id, 'n1');
    });

    test('locked notes stay title-only', () async {
      await addNote('n2', 'corplex-locked:v1:k:quokkasecret');
      final search = SearchIndex(db);
      expect(await search.search('quokkasecret'), isEmpty);
    });
  });
}

String _q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
