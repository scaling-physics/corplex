import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ink/ink_model.dart';
import '../ink/ink_tools.dart' show sketchPaperColor;
import '../notes/math_render.dart';
import '../notes/note_table.dart';
import 'export_images.dart' show ExportPhoto;
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
      style: style(size, isBold: forceBold || r.bold, isItalic: r.italic)
          .copyWith(
            decoration: r.strike ? pw.TextDecoration.lineThrough : null,
            background: r.highlight == null
                ? null
                : pw.BoxDecoration(color: PdfColor.fromHex(r.highlight!)),
          ),
    );
  }

  pw.Widget tableWidget(NoteTable t) {
    pw.Widget cell(String text, bool head) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: style(10, isBold: head)),
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        children: [
          for (final (i, row) in t.rows.indexed)
            pw.TableRow(
              repeat: t.header && i == 0,
              decoration: t.header && i == 0
                  ? pw.BoxDecoration(color: PdfColor.fromHex('EFEBE4'))
                  : null,
              children: [for (final c in row) cell(c, t.header && i == 0)],
            ),
        ],
      ),
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

    if (b.kind == BlockKind.code) {
      // The built-in Courier only covers Latin-1; a line with anything else
      // falls back to Roboto rather than failing the whole export.
      final latin1 = b.text.runes.every((r) => r < 0x100);
      final text = b.text.replaceAll('\t', '    ');
      return pw.Container(
        width: double.infinity,
        color: PdfColor.fromHex('F0EDE8'),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: pw.Text(
          text.isEmpty ? ' ' : text,
          style: latin1
              ? pw.TextStyle(font: pw.Font.courier(), fontSize: 10)
              : style(10),
        ),
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
    if (b.kind == BlockKind.image) return sketchWidget(b.sketch!);
    if (b.kind == BlockKind.table) return tableWidget(b.table!);
    if (b.kind == BlockKind.photo) return photoWidget(b.photo!, style(9));
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
      BlockKind.caption => rich(10, before: 2, after: 10),
      BlockKind.displayMath ||
      BlockKind.code ||
      BlockKind.image ||
      BlockKind.photo ||
      BlockKind.table => pw.SizedBox(),
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

// A4 text width with the 56 pt margins used above.
const _textWidth = 595.28 - 112;
const _maxSketchHeight = 660.0;

// About 70% of an A4 page's height.
const _maxPhotoHeight = 590.0;

/// An attached image at full text width (narrower only if it would be taller
/// than ~70% of a page), with its caption underneath when it has one.
pw.Widget photoWidget(ExportPhoto photo, pw.TextStyle captionStyle) {
  var width = _textWidth;
  var height = width * photo.aspect;
  if (height > _maxPhotoHeight) {
    width = width * _maxPhotoHeight / height;
    height = _maxPhotoHeight;
  }
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Column(
      children: [
        pw.Image(
          pw.MemoryImage(photo.bytes),
          width: width,
          height: height,
          fit: pw.BoxFit.contain,
        ),
        if (photo.caption != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(photo.caption!, style: captionStyle),
          ),
      ],
    ),
  );
}

/// A drawing as vector paths (no rasterising) on the sketch paper colour,
/// as wide as the text (narrower only if it would be taller than a page).
/// Pen strokes use their average pressure for width, like the SVG export.
pw.Widget sketchWidget(Sketch sketch) {
  var width = _textWidth;
  var height = width * sketch.aspect;
  if (height > _maxSketchHeight) {
    width = width * _maxSketchHeight / height;
    height = _maxSketchHeight;
  }
  PdfColor col(Color c) => PdfColor(c.r, c.g, c.b);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Center(
      child: pw.SizedBox(
        width: width,
        height: height,
        child: pw.CustomPaint(
          size: PdfPoint(width, height),
          painter: (canvas, size) {
            canvas
              ..setFillColor(col(sketchPaperColor))
              ..drawRect(0, 0, size.x, size.y)
              ..fillPath();
            final ordered = [
              ...sketch.strokes.where((s) => s.tool == InkTool.highlighter),
              ...sketch.strokes.where((s) => s.tool == InkTool.pen),
            ];
            double px(InkPoint p) => p.x * width;
            double py(InkPoint p) => size.y - p.y * width;
            for (final s in ordered) {
              if (s.points.isEmpty) continue;
              final hl = s.tool == InkTool.highlighter;
              final pressure = hl
                  ? 0.5
                  : s.points.fold<double>(0, (a, p) => a + p.p) /
                        s.points.length;
              final w = hl
                  ? s.width * width
                  : s.width * width * (0.45 + 0.9 * pressure);
              canvas
                ..saveContext()
                ..setGraphicState(
                  PdfGraphicState(
                    opacity: hl ? 0.5 : 1,
                    strokeOpacity: hl ? 0.5 : 1,
                  ),
                );
              if (s.points.length == 1) {
                final p = s.points.single;
                canvas
                  ..setFillColor(col(s.color))
                  ..drawEllipse(px(p), py(p), w / 2, w / 2)
                  ..fillPath();
              } else {
                canvas
                  ..setStrokeColor(col(s.color))
                  ..setLineWidth(w)
                  ..setLineCap(PdfLineCap.round)
                  ..setLineJoin(PdfLineJoin.round)
                  ..moveTo(px(s.points.first), py(s.points.first));
                for (final p in s.points.skip(1)) {
                  canvas.lineTo(px(p), py(p));
                }
                canvas.strokePath();
              }
              canvas.restoreContext();
            }
          },
        ),
      ),
    ),
  );
}
