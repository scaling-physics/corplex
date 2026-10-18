import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/shape_recognizer.dart';

/// Hand-drawn wobble, deterministic.
Offset _wobble(Offset p, int i, [double amount = 0.004]) => Offset(
  p.dx + amount * math.sin(i * 1.7),
  p.dy + amount * math.cos(i * 2.3),
);

List<InkPoint> _through(
  List<Offset> verts, {
  bool close = false,
  int per = 12,
}) {
  final all = close ? [...verts, verts.first] : verts;
  final out = <Offset>[];
  for (var i = 1; i < all.length; i++) {
    for (var k = 0; k < per; k++) {
      out.add(Offset.lerp(all[i - 1], all[i], k / per)!);
    }
  }
  out.add(all.last);
  return [
    for (var i = 0; i < out.length; i++)
      InkPoint(_wobble(out[i], i).dx, _wobble(out[i], i).dy, 0.7),
  ];
}

Rect _box(List<InkPoint> pts) {
  final xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

void main() {
  test('a wobbly line becomes a straight one', () {
    final shape = recognizeShape(
      _through([const Offset(0.1, 0.1), const Offset(0.7, 0.4)], per: 40),
    )!;
    final a = shape.first.offset, b = shape.last.offset;
    for (final p in shape) {
      final rel = p.offset - a;
      final dir = (b - a) / (b - a).distance;
      expect((rel.dx * dir.dy - rel.dy * dir.dx).abs(), lessThan(1e-9));
    }
    expect(shape.every((p) => p.p == 0.5), isTrue);
    expect(shape.length, greaterThan(20)); // dense enough to draw smoothly
  });

  test('a nearly level line is made level', () {
    final shape = recognizeShape(
      _through([const Offset(0.1, 0.3), const Offset(0.8, 0.31)], per: 40),
    )!;
    expect(shape.first.y, shape.last.y);
  });

  test('a circle', () {
    const c = Offset(0.5, 0.4);
    final pts = [
      for (var i = 0; i <= 60; i++)
        () {
          final a = 2 * math.pi * i / 60 + 1;
          final r = 0.15 + 0.004 * math.sin(i * 1.3);
          final o = c + Offset(math.cos(a), math.sin(a)) * r;
          return InkPoint(o.dx, o.dy, 0.6);
        }(),
    ];
    final shape = recognizeShape(pts)!;
    final box = _box(shape);
    expect(box.width, closeTo(box.height, 0.005));
    expect(box.center.dx, closeTo(0.5, 0.01));
    expect((shape.first.offset - shape.last.offset).distance, lessThan(1e-6));
  });

  test('an ellipse keeps its proportions', () {
    const c = Offset(0.5, 0.4);
    final pts = [
      for (var i = 0; i <= 80; i++)
        InkPoint(
          c.dx + 0.3 * math.cos(2 * math.pi * i / 80),
          c.dy + 0.12 * math.sin(2 * math.pi * i / 80),
          0.5,
        ),
    ];
    final box = _box(recognizeShape(pts)!);
    expect(box.width, closeTo(0.6, 0.01));
    expect(box.height, closeTo(0.24, 0.01));
  });

  test('a rectangle, with its last corner not quite closed', () {
    final pts = _through(const [
      Offset(0.2, 0.2),
      Offset(0.7, 0.21),
      Offset(0.69, 0.5),
      Offset(0.21, 0.49),
      Offset(0.205, 0.22),
    ]);
    final shape = recognizeShape(pts)!;
    // Corners are exact: every point lies on the box edge.
    final box = _box(shape);
    for (final p in shape) {
      final onEdge =
          (p.x - box.left).abs() < 1e-6 ||
          (p.x - box.right).abs() < 1e-6 ||
          (p.y - box.top).abs() < 1e-6 ||
          (p.y - box.bottom).abs() < 1e-6;
      expect(onEdge, isTrue);
    }
    expect(box.width, closeTo(0.5, 0.03));
    expect(box.height, closeTo(0.29, 0.03));
  });

  test('a triangle', () {
    final pts = _through(const [
      Offset(0.5, 0.15),
      Offset(0.8, 0.6),
      Offset(0.2, 0.62),
    ], close: true);
    final shape = recognizeShape(pts)!;
    final box = _box(shape);
    expect(box.width, closeTo(0.6, 0.03));
    expect(box.height, closeTo(0.47, 0.03));
    // Still a triangle: the point halfway up the left edge is on a line.
    final top = shape.reduce((a, b) => a.y < b.y ? a : b);
    expect(top.x, closeTo(0.5, 0.03));
  });

  test('an arrow, shaft then head', () {
    const tip = Offset(0.8, 0.3);
    final pts = _through([
      const Offset(0.1, 0.3),
      tip,
      const Offset(0.7, 0.22),
      tip,
      const Offset(0.7, 0.38),
    ], per: 14);
    final shape = recognizeShape(pts)!;
    // Passes the tip three times: end of the shaft and both barbs.
    final nearTip = shape.where((p) => (p.offset - tip).distance < 0.02);
    expect(nearTip.length, greaterThanOrEqualTo(3));
    expect(shape.first.x, closeTo(0.1, 0.01));
  });

  test('scribbles and letters are left alone', () {
    // zigzag
    expect(
      recognizeShape(
        _through(const [
          Offset(0.1, 0.1),
          Offset(0.3, 0.3),
          Offset(0.2, 0.1),
          Offset(0.4, 0.3),
          Offset(0.3, 0.1),
          Offset(0.5, 0.3),
        ]),
      ),
      isNull,
    );
    // a C
    final c = [
      for (var i = 0; i <= 30; i++)
        InkPoint(
          0.4 + 0.15 * math.cos(0.8 + 4.6 * i / 30),
          0.4 + 0.15 * math.sin(0.8 + 4.6 * i / 30),
          0.5,
        ),
    ];
    expect(recognizeShape(c), isNull);
    // an S-curve
    final s = [
      for (var i = 0; i <= 40; i++)
        InkPoint(
          0.1 + 0.4 * i / 40,
          0.3 + 0.1 * math.sin(i / 40 * 2 * math.pi),
          0.5,
        ),
    ];
    expect(recognizeShape(s), isNull);
    // a dense random-ish scribble
    final scribble = [
      for (var i = 0; i < 80; i++)
        InkPoint(
          0.3 + 0.2 * math.sin(i * 0.9) * math.cos(i * 0.31),
          0.3 + 0.2 * math.cos(i * 1.3),
          0.5,
        ),
    ];
    expect(recognizeShape(scribble), isNull);
  });

  test('a dot, a tick and a tiny mark are ignored', () {
    expect(recognizeShape(const [InkPoint(0.1, 0.1, 0.5)]), isNull);
    expect(
      recognizeShape(_through(const [Offset(0.1, 0.1), Offset(0.12, 0.11)])),
      isNull,
    );
  });

  test('a circle drawn twice over is not snapped', () {
    final pts = [
      for (var i = 0; i <= 120; i++)
        InkPoint(
          0.5 + 0.15 * math.cos(2 * math.pi * i / 60),
          0.4 + 0.15 * math.sin(2 * math.pi * i / 60),
          0.5,
        ),
    ];
    expect(recognizeShape(pts), isNull);
  });
}
