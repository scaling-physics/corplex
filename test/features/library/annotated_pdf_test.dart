import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:corplex/features/library/annotated_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List _bytes(String s) => Uint8List.fromList(latin1.encode(s));

/// A hand-built one-page PDF (classic xref table) with the given page entries.
Uint8List _classicPdf(String pageExtra, {String trailerExtra = ''}) {
  final b = BytesBuilder();
  final offs = <int>[];
  void obj(String body) {
    offs.add(b.length);
    b.add(latin1.encode('${offs.length} 0 obj\n$body\nendobj\n'));
  }

  b.add(latin1.encode('%PDF-1.4\n'));
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj('<< /Type /Page /Parent 2 0 R $pageExtra >>');
  final x = b.length;
  b.add(latin1.encode('xref\n0 4\n0000000000 65535 f \n'));
  for (final o in offs) {
    b.add(latin1.encode('${o.toString().padLeft(10, '0')} 00000 n \n'));
  }
  b.add(
    latin1.encode(
      'trailer\n<< /Size 4 /Root 1 0 R $trailerExtra >>\nstartxref\n$x\n%%EOF\n',
    ),
  );
  return b.toBytes();
}

/// Same document, but with an xref *stream* and the catalog, page tree and
/// page packed in an object stream.
Uint8List _streamPdf(String pageExtra) {
  final b = BytesBuilder();
  b.add(latin1.encode('%PDF-1.5\n'));
  final bodies = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R $pageExtra >>',
  ];
  var header = '';
  var data = '';
  for (var i = 0; i < bodies.length; i++) {
    header += '${i + 1} ${data.length} ';
    data += '${bodies[i]}\n';
  }
  final content = latin1.encode(header + data);
  final packed = ZLibCodec().encode(content);
  final objOff = b.length;
  b.add(
    latin1.encode(
      '4 0 obj\n<< /Type /ObjStm /N 3 /First ${header.length} '
      '/Filter /FlateDecode /Length ${packed.length} >>\nstream\n',
    ),
  );
  b.add(packed);
  b.add(latin1.encode('\nendstream\nendobj\n'));
  final xOff = b.length;
  final rows = BytesBuilder();
  rows.add([0, 0, 0, 0, 0, 0xFF]); // 0 free (W 1 3 2)
  for (var i = 0; i < 3; i++) {
    rows.add([2, 0, 0, 4, 0, i]); // in objstm 4, index i
  }
  rows.add([1, objOff >> 16, (objOff >> 8) & 255, objOff & 255, 0, 0]);
  rows.add([1, xOff >> 16, (xOff >> 8) & 255, xOff & 255, 0, 0]);
  final r = rows.toBytes();
  b.add(
    latin1.encode(
      '5 0 obj\n<< /Type /XRef /Size 6 /W [1 3 2] /Root 1 0 R '
      '/Length ${r.length} >>\nstream\n',
    ),
  );
  b.add(r);
  b.add(latin1.encode('\nendstream\nendobj\nstartxref\n$xOff\n%%EOF\n'));
  return b.toBytes();
}

List<double> _nums(Object? v) => [
  for (final e in v as List) (e as num).toDouble(),
];

String _text(Object? v) => latin1.decode((v as PdfStr).bytes);

void main() {
  group('PageGeometry', () {
    test('unrotated page with an offset crop box', () {
      final g = PageGeometry(x0: 50, y0: 100, x1: 250, y1: 300);
      expect(g.toUser(0, 0), [50, 300]); // top-left
      expect(g.toUser(1, 1), [250, 100]); // bottom-right
      expect(g.toUser(.5, .25), [150, 250]);
    });

    test('rotation maps the displayed corners to the right user corners', () {
      // 100 wide, 200 tall box at (10, 20).
      PageGeometry g(int r) =>
          PageGeometry(x0: 10, y0: 20, x1: 110, y1: 220, rotate: r);
      expect(g(90).displayWidth, 200);
      expect(g(90).displayHeight, 100);
      // Displayed top-left is the original bottom-left when turned 90 CW.
      expect(g(90).toUser(0, 0), [10, 20]);
      expect(g(90).toUser(1, 0), [10, 220]);
      expect(g(90).toUser(0, 1), [110, 20]);
      // 180: top-left shows the original bottom-right.
      expect(g(180).toUser(0, 0), [110, 20]);
      expect(g(180).toUser(1, 1), [10, 220]);
      // 270: top-left shows the original top-right.
      expect(g(270).toUser(0, 0), [110, 220]);
      expect(g(270).toUser(1, 0), [110, 20]);
      expect(g(270).toUser(0, 1), [10, 220]);
    });
  });

  group('writeAnnotatedPdf', () {
    const hl = HighlightMark(
      page: 1,
      rects: [
        [0.1, 0.2, 0.5, 0.25],
        [0.1, 0.25, 0.3, 0.3],
      ],
      rgb: 0xF2D66B,
      comment: 'Key claim – check',
    );
    const stroke = InkMark(
      page: 1,
      points: [
        [0.1, 0.1],
        [0.5, 0.1],
        [0.5, 0.5],
      ],
      rgb: 0xFF0000,
    );

    test('round-trips through a PDF made by the pdf package', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (_) => pw.Text('Page one')));
      doc.addPage(
        pw.Page(
          orientation: pw.PageOrientation.landscape,
          build: (_) => pw.Text('Page two'),
        ),
      );
      final original = await doc.save();
      final r = writeAnnotatedPdf(
        original,
        highlights: [
          hl,
          const HighlightMark(
            page: 2,
            rects: [
              [0, 0, 1, 0.1],
            ],
            rgb: 0x00FF00,
          ),
          const HighlightMark(
            page: 9,
            rects: [
              [0, 0, 1, 1],
            ],
            rgb: 0,
          ),
        ],
        ink: [stroke],
      );
      expect(r.written, 3);
      expect(r.skipped, 1);
      // Incremental: the original is an untouched prefix.
      expect(r.bytes.sublist(0, original.length), original);
      final annots = readAnnotations(r.bytes, 2);
      expect(annots.map((a) => '${a.page}:${a.subtype}'), [
        '1:Highlight',
        '1:Ink',
        '2:Highlight',
      ]);
      final h = annots[0].dict;
      expect(_text(h['T']), 'Corplex');
      expect(_nums(h['C'])[0], closeTo(0xF2 / 255, 1e-3));
      expect(_nums(h['QuadPoints']).length, 16);
      expect(h['AP'], isA<Map>());
      // A4 page, 595.28 x 841.89: first quad's top-left.
      final q = _nums(h['QuadPoints']);
      expect(q[0], closeTo(595.28 * 0.1, 0.5));
      expect(q[1], closeTo(841.89 * 0.8, 0.5));
      expect((h['Contents'] as PdfStr).bytes.sublist(0, 2), [0xFE, 0xFF]);
      final inkList = (annots[1].dict['InkList'] as List).single as List;
      expect(inkList.length, 6);
      expect(annots[1].dict['BS'], isA<Map>());
    });

    test('honours CropBox offset and Rotate', () {
      final pdf = _classicPdf(
        '/MediaBox [0 0 612 792] /CropBox [10 20 110 220] /Rotate 90',
      );
      final r = writeAnnotatedPdf(
        pdf,
        highlights: [
          const HighlightMark(
            page: 1,
            rects: [
              [0, 0, 1, 1],
            ],
            rgb: 0,
          ),
        ],
      );
      final q = _nums(readAnnotations(r.bytes, 1).single.dict['QuadPoints']);
      // Displayed TL, TR, BL, BR for a 90 degree page.
      expect(q, [10, 20, 10, 220, 110, 20, 110, 220]);
    });

    test('inherits MediaBox from the page tree and keeps old annotations', () {
      final pdf = _classicPdf(
        '/MediaBox [0 0 200 100] /Annots [<< /Type /Annot /Subtype /Text /Rect [0 0 1 1] >>]',
      );
      final r = writeAnnotatedPdf(pdf, highlights: [hl]);
      final a = readAnnotations(r.bytes, 1);
      expect(a.map((e) => e.subtype), ['Text', 'Highlight']);
      expect(_nums(a[1].dict['QuadPoints'])[0], closeTo(20, 1e-3));
    });

    test('works on xref streams with object streams', () {
      final pdf = _streamPdf('/MediaBox [0 0 200 100]');
      final r = writeAnnotatedPdf(pdf, highlights: [hl], ink: [stroke]);
      expect(r.written, 2);
      // The update ends with an xref stream, not a table.
      final tail = latin1.decode(
        r.bytes.sublist(r.bytes.length - 400),
        allowInvalid: true,
      );
      expect(tail.contains('/Type /XRef') || tail.contains('/XRef'), isTrue);
      expect(
        latin1
            .decode(r.bytes.sublist(pdf.length), allowInvalid: true)
            .contains('\nxref\n'),
        isFalse,
      );
      final a = readAnnotations(r.bytes, 1);
      expect(a.map((e) => e.subtype), ['Highlight', 'Ink']);
      // Writing a second time on top of our own output also works.
      final again = writeAnnotatedPdf(r.bytes, highlights: [hl]);
      expect(readAnnotations(again.bytes, 1).length, 3);
    });

    test('refuses encrypted PDFs with a readable message', () {
      final pdf = _classicPdf(
        '/MediaBox [0 0 200 100]',
        trailerExtra: '/Encrypt 3 0 R',
      );
      expect(
        () => writeAnnotatedPdf(pdf, highlights: [hl]),
        throwsA(
          isA<AnnotatedPdfException>().having(
            (e) => e.message,
            'message',
            contains('encrypted'),
          ),
        ),
      );
    });

    test('refuses garbage', () {
      expect(
        () => writeAnnotatedPdf(_bytes('not a pdf at all'), highlights: [hl]),
        throwsA(isA<AnnotatedPdfException>()),
      );
      expect(
        () => writeAnnotatedPdf(
          _bytes('%PDF-1.4\nstartxref\n9999\n%%EOF'),
          highlights: [hl],
        ),
        throwsA(isA<AnnotatedPdfException>()),
      );
    });

    test('with nothing to write the file is returned as is', () {
      final pdf = _classicPdf('/MediaBox [0 0 200 100]');
      final r = writeAnnotatedPdf(pdf);
      expect(r.bytes, pdf);
      expect(r.written, 0);
    });
  });
}
