// On-device smoke test: exercises each feature through its real plugin
// (pdfium, ML Kit / Vision, the recorder, asset bundle, file system) — the
// parts widget tests replace with fakes. Run on an emulator or device:
//
//   adb shell pm grant com.corplex.corplex android.permission.RECORD_AUDIO
//   flutter test integration_test/smoke_test.dart -d <device>
//
// It needs no network; OpenAlex/Crossref lookups are not covered.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:corplex/features/library/annotated_pdf.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/library/library_actions.dart';
import 'package:corplex/features/library/paper_cover.dart';
import 'package:corplex/features/notes/math_render.dart';
import 'package:corplex/features/ocr/ocr_engine.dart';
import 'package:corplex/features/ocr/ocr_service.dart';
import 'package:corplex/features/ocr/pdf_pages.dart';
import 'package:corplex/features/voice/voice_services.dart';
import 'package:corplex/features/read_aloud/speaker.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/sketch_render.dart';
import 'package:corplex/main.dart' as app;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

const _doi = '10.1038/nature14539';

Future<String> _write(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// A born-digital PDF with a real text layer.
Future<Uint8List> _textPdf() {
  final doc = pw.Document()
    ..addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Deep learning'),
            pw.Text('doi:$_doi'),
            pw.Text('Representation learning with multiple layers.'),
          ],
        ),
      ),
    )
    ..addPage(pw.Page(build: (_) => pw.Text('Second page')));
  return doc.save();
}

/// Black text on white, drawn by the engine, as PNG — a "scan".
Future<Uint8List> _textImage(List<String> lines) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 1600, 900),
      Paint()..color = Colors.white,
    );
  var y = 80.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(color: Colors.black, fontSize: 56),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1500);
    painter.paint(canvas, Offset(60, y));
    y += 110;
  }
  final image = await recorder.endRecording().toImage(1600, 900);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches with the real plugins', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF engine: text layer, cover, identifier, page count', (
    tester,
  ) async {
    final path = await _write('smoke_text.pdf', await _textPdf());
    final doc = await PdfDocument.openFile(path);
    final text = (await doc.pages.first.loadStructuredText()).fullText;
    await doc.dispose();
    expect(text, contains('Deep learning')); // find in document

    final cover = await renderFirstPage(path);
    expect(cover, isNotNull);
    expect(cover!.length, greaterThan(1000));

    final start = await readPdfStart(path);
    expect(start.id?.value, _doi);
    expect(start.pageCount, 2);
    expect(start.scanned, isFalse);
  });

  testWidgets('OCR: recognises a scan and finds its DOI on import', (
    tester,
  ) async {
    final png = await _textImage([
      'Deep learning',
      'doi:$_doi',
      'Convolutional networks',
    ]);
    final page = await PlatformOcrEngine().recognize(png);
    expect(page.text.toLowerCase(), contains('deep learning'));

    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    for (var i = 0; i < 2; i++) {
      doc.addPage(pw.Page(build: (_) => pw.Image(image)));
    }
    final path = await _write('smoke_scan.pdf', await doc.save());
    final db = AppDatabase.inMemoryForTesting();
    addTearDown(db.close);
    await db
        .into(db.papers)
        .insert(PapersCompanion.insert(id: const Value('s1'), title: 'scan'));
    final ocr = OcrService(db, PlatformOcrEngine(), PdfrxPages.open);
    final start = await readPdfStart(path, ocr: ocr, paperId: 's1');
    expect(start.scanned, isTrue);
    expect(start.id?.value, _doi);
  });

  testWidgets('export with highlights: the result still opens', (tester) async {
    final result = writeAnnotatedPdf(
      await _textPdf(),
      highlights: [
        const HighlightMark(
          page: 1,
          rects: [
            [0.1, 0.1, 0.5, 0.13],
          ],
          rgb: 0xFFE082,
          comment: 'smoke',
        ),
      ],
      ink: [
        const InkMark(
          page: 2,
          points: [
            [0.2, 0.2],
            [0.4, 0.3],
          ],
          rgb: 0x90CAF9,
        ),
      ],
    );
    expect(result.written, 2);
    final doc = await PdfDocument.openData(result.bytes);
    expect(doc.pages.length, 2);
    await doc.dispose();
  });

  testWidgets('maths renders to an image', (tester) async {
    final image = await renderMathPng(r'\frac{a}{b} + \sqrt{x^2}');
    expect(image, isNotNull);
  });

  testWidgets('CSL styles load from the asset bundle', (tester) async {
    for (final style in [
      CitationStyle.apa,
      CitationStyle.ieee,
      CitationStyle.nature,
      CitationStyle.vancouver,
    ]) {
      expect(await style.ensureLoaded(), isNotNull, reason: style.label);
    }
  });

  testWidgets('voice: the recorder records a file', (tester) async {
    final recorder = PluginVoiceRecorder();
    expect(await recorder.ensureAccess(), MicAccess.granted);
    await recorder.start();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    final path = await recorder.stop();
    await recorder.dispose();
    expect(path, isNotNull);
    expect(await File(path!).length(), greaterThan(0));
    await File(path).delete();
  });

  testWidgets('Markdown export builds an archive', (tester) async {
    final db = AppDatabase.inMemoryForTesting();
    addTearDown(db.close);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Smoke note'),
          ),
        );
    final result = await buildVaultArchive(db);
    expect(result.notes, 1);
    expect(
      result.archive.files.map((f) => f.name),
      contains(endsWith('Smoke note.md')),
    );
  });

  testWidgets('read aloud: the system voice speaks a sentence', (tester) async {
    final speaker = ChannelSpeaker();
    final finished = await speaker
        .speak('Place cells fire in one part of the arena.', rate: 1.5)
        .timeout(const Duration(seconds: 30));
    expect(finished, isTrue);
    await speaker.stop();
  });

  testWidgets('handwriting: a drawing renders and OCR reads it without '
      'error', (tester) async {
    const sketch = Sketch(
      aspect: 0.3,
      strokes: [
        InkStroke(
          tool: InkTool.pen,
          color: ui.Color(0xFF000000),
          width: 0.01,
          points: [InkPoint(0.1, 0.1, 0.5), InkPoint(0.9, 0.2, 0.5)],
        ),
      ],
    );
    final png = await renderSketchPng(sketch, width: 800);
    expect(png.take(4), [137, 80, 78, 71]);
    // A line isn't words; this checks the native path runs on a drawing.
    await const PlatformOcrEngine().recognize(png);
  });
}
