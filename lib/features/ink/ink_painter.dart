import 'package:flutter/material.dart';

import 'ink_model.dart';

/// Paints strokes at the given canvas width. Pen lines swell and thin with
/// pressure; highlighter lines are flat, translucent (50%) and drawn beneath the
/// pen so they never mute the ink on top.
class InkPainter extends CustomPainter {
  InkPainter({required this.strokes, super.repaint});

  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width;
    for (final s in strokes.where((s) => s.tool == InkTool.highlighter)) {
      paintStroke(canvas, s, scale);
    }
    for (final s in strokes.where((s) => s.tool == InkTool.pen)) {
      paintStroke(canvas, s, scale);
    }
  }

  static void paintStroke(Canvas canvas, InkStroke stroke, double scale) {
    final points = stroke.points;
    if (points.isEmpty) return;

    if (stroke.tool == InkTool.highlighter) {
      final paint = Paint()
        ..color = stroke.color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.width * scale;
      final path = Path()..moveTo(points[0].x * scale, points[0].y * scale);
      for (final p in points.skip(1)) {
        path.lineTo(p.x * scale, p.y * scale);
      }
      if (points.length == 1) {
        canvas.drawCircle(
          points[0].offset * scale,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawPath(path, paint);
      }
      return;
    }

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    double widthAt(InkPoint p) => stroke.width * scale * (0.45 + 0.9 * p.p);

    if (points.length == 1) {
      canvas.drawCircle(
        points[0].offset * scale,
        widthAt(points[0]) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    // Segments between midpoints, each a smooth quadratic curve through the
    // real point, with width eased from the neighbouring pressures.
    var from = points[0].offset * scale;
    for (var i = 1; i < points.length; i++) {
      final control = points[i - 1].offset * scale;
      final to = i == points.length - 1
          ? points[i].offset * scale
          : (points[i - 1].offset + points[i].offset) / 2 * scale;
      paint.strokeWidth = (widthAt(points[i - 1]) + widthAt(points[i])) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy),
        paint,
      );
      from = to;
    }
  }

  @override
  bool shouldRepaint(InkPainter old) => !identical(old.strokes, strokes);
}
