import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'ink_model.dart';
import 'ink_painter.dart';
import 'ink_tools.dart' show sketchPaperColor;

/// A drawing as a PNG, [width] pixels wide (its height follows its aspect),
/// on the light sketch paper unless [background] says otherwise (pass
/// transparent for an image laid over something else). Used by exports,
/// printing and handwriting recognition. Needs the Flutter engine (any
/// running app or widget test; in tests run it inside `runAsync`).
Future<Uint8List> renderSketchPng(
  Sketch sketch, {
  double width = 1200,
  Color background = sketchPaperColor,
}) async {
  final height = (width * sketch.aspect).ceilToDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  if (background.a > 0) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = background,
    );
  }
  InkPainter(strokes: sketch.strokes).paint(canvas, Size(width, height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.ceil());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A drawing as SVG text, [width] units wide: pure Dart, vector, for
/// Markdown and LaTeX exports. Pen strokes are paths whose width follows
/// the stroke's average pressure (SVG has no per-point width);
/// highlighter strokes are drawn first, at half opacity.
String sketchToSvg(Sketch sketch, {double width = 800}) {
  final height = width * sketch.aspect;
  String n(double v) => v.toStringAsFixed(2);
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  final out = StringBuffer()
    ..write(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n(width)} '
      '${n(height)}" width="${n(width)}" height="${n(height)}">',
    );
  final ordered = [
    ...sketch.strokes.where((s) => s.tool == InkTool.highlighter),
    ...sketch.strokes.where((s) => s.tool == InkTool.pen),
  ];
  for (final s in ordered) {
    if (s.points.isEmpty) continue;
    final highlighter = s.tool == InkTool.highlighter;
    final avgPressure = highlighter
        ? 0.5
        : s.points.fold<double>(0, (a, p) => a + p.p) / s.points.length;
    final strokeWidth = highlighter
        ? s.width * width
        : s.width * width * (0.45 + 0.9 * avgPressure);
    final opacity = highlighter ? ' stroke-opacity="0.5"' : '';
    if (s.points.length == 1) {
      final p = s.points.single;
      out.write(
        '<circle cx="${n(p.x * width)}" cy="${n(p.y * width)}" '
        'r="${n(strokeWidth / 2)}" fill="${hex(s.color)}"'
        '${highlighter ? ' fill-opacity="0.5"' : ''}/>',
      );
      continue;
    }
    final d = StringBuffer(
      'M${n(s.points.first.x * width)} '
      '${n(s.points.first.y * width)}',
    );
    for (final p in s.points.skip(1)) {
      d.write(' L${n(p.x * width)} ${n(p.y * width)}');
    }
    out.write(
      '<path d="$d" fill="none" stroke="${hex(s.color)}"$opacity '
      'stroke-width="${n(strokeWidth)}" stroke-linecap="round" '
      'stroke-linejoin="round"/>',
    );
  }
  out.write('</svg>');
  return out.toString();
}
