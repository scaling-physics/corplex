import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../notes/math_render.dart';
import 'export_model.dart';

/// Loads a bundled font file's bytes. Injectable so tests can read from
/// disk instead of the asset bundle.
typedef FontLoader = Future<ByteData> Function(String asset);

/// A paginated A4 PDF of [doc]. Roboto is embedded so curly quotes, dashes
/// and accented letters render; the PDF base fonts can't.
Future<Uint8List> exportToPdf(ExportDoc doc, {FontLoader? loadFont}) async {
  final load = loadFont ?? rootBundle.load;
  final regular = pw.Font.ttf(await load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await load('assets/fonts/Roboto-Bold.ttf'));
  final italic = pw.Font.ttf(await load('assets/fonts/Roboto-Italic.ttf'));
  final boldItalic = pw.Font.ttf(
    await load('assets/fonts/Roboto-BoldItalic.ttf'),
  );

  pw.TextStyle style(
    double size, {
    bool isBold = false,
    bool isItalic = false,
  }) => pw.TextStyle(
    font: regular,
    fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
    fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
    fontBold: bold,
    fontNormal: regular,
    fontItalic: italic,
    fontBoldItalic: boldItalic,
    fontSize: size,
    lineSpacing: 3,
  );

  // Equations are drawn up front (async); one that won't render falls back
  // to its LaTeX source as text.
  final maths = <String, MathImage?>{};
  for (final b in doc.blocks) {
    for (final r in b.runs) {
      if (!r.math) continue;
      final display = b.kind == BlockKind.displayMath;
      maths['${display ? 'D' : 'I'}${r.text}'] ??= await renderMathPng(
        r.text,
        display: display,
        fontSize: display ? 14 : 11,
      );
    }
  }

  pw.InlineSpan span(Run r, double size, {bool forceBold = false}) {
    if (r.math) {
      final img = maths['I${r.text}'];
      if (img == null) {
        return pw.TextSpan(text: '\$${r.text}\$', style: style(size));
      }
      return pw.WidgetSpan(
        baseline: img.descent,
        child: pw.Image(
          pw.MemoryImage(img.png),
          width: img.width,
          height: img.height,
        ),
      );
    }
    return pw.TextSpan(
      text: r.link == null ? r.text : '${r.text} (${r.link})',
      style: style(
        size,
        isBold: forceBold || r.bold,
        isItalic: r.italic,
      ).copyWith(decoration: r.strike ? pw.TextDecoration.lineThrough : null),
    );
  }

  pw.Widget block(ExportBlock b) {
    pw.Widget rich(
      double size, {
      bool isBold = false,
      double before = 0,
      double after = 6,
      double indent = 0,
      String marker = '',
    }) {
      final spans = [
        if (marker.isNotEmpty) pw.TextSpan(text: marker, style: style(size)),
        for (final r in b.runs) span(r, size, forceBold: isBold),
      ];
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: indent, top: before, bottom: after),
        child: pw.RichText(text: pw.TextSpan(children: spans)),
      );
    }

    if (b.kind == BlockKind.displayMath) {
      final src = b.runs.isEmpty ? '' : b.runs.first.text;
      final img = maths['D$src'];
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Center(
          child: img == null
              ? pw.Text(src, style: style(11, isItalic: true))
              : pw.Image(
                  pw.MemoryImage(img.png),
                  width: img.width > 480 ? 480 : img.width,
                  fit: pw.BoxFit.contain,
                ),
        ),
      );
    }
    return switch (b.kind) {
      BlockKind.heading1 => rich(20, isBold: true, before: 14, after: 6),
      BlockKind.heading2 => rich(16, isBold: true, before: 10, after: 4),
      BlockKind.heading3 => rich(13, isBold: true, before: 8, after: 3),
      BlockKind.bullet => rich(11, indent: 16, marker: '•  ', after: 3),
      BlockKind.ordered => rich(
        11,
        indent: 16,
        marker: '${b.ordinal}.  ',
        after: 3,
      ),
      BlockKind.quote => pw.Container(
        margin: const pw.EdgeInsets.only(left: 12, bottom: 6),
        padding: const pw.EdgeInsets.only(left: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey500, width: 2),
          ),
        ),
        child: rich(11, after: 0),
      ),
      BlockKind.displayMath => pw.SizedBox(),
      BlockKind.paragraph =>
        b.runs.every((r) => r.text.isEmpty) ? pw.SizedBox(height: 6) : rich(11),
    };
  }

  final pdf = pw.Document(title: doc.title, creator: 'Corplex');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(56),
      build: (_) => [
        if (doc.title.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 14),
            child: pw.Text(doc.title.trim(), style: style(26, isBold: true)),
          ),
        for (final b in doc.blocks) block(b),
      ],
    ),
  );
  return pdf.save();
}
