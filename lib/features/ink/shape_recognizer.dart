import 'dart:math' as math;
import 'dart:ui';

import 'ink_model.dart';

/// Turns a hand-drawn stroke into the clean shape it was meant to be — a
/// line, circle / ellipse, rectangle, triangle or arrow — or null when the
/// stroke is none of those (a letter, a scribble, a squiggle), so nothing
/// changes. Pure and scale-free: [points] can be in any uniform unit; pass
/// [minLength] in the same unit (the shortest stroke worth snapping, 8% of
/// the canvas width by default). The result is dense enough to draw
/// smoothly with the ordinary painter, at a constant pressure.
List<InkPoint>? recognizeShape(
  List<InkPoint> points, {
  double minLength = 0.08,
}) {
  final pts = <Offset>[];
  for (final p in points) {
    if (pts.isEmpty || (p.offset - pts.last).distance > 1e-9) pts.add(p.offset);
  }
  if (pts.length < 4) return null;
  final length = _pathLength(pts);
  if (length < minLength) return null;
  final step = minLength / 8;
  final gap = (pts.last - pts.first).distance;

  final List<Offset>? shape = gap < length * 0.2
      ? _closedShape(pts, length, step)
      : (_line(pts, length, gap, step) ?? _arrow(pts, length, step));
  if (shape == null) return null;
  return [for (final o in shape) InkPoint(o.dx, o.dy, 0.5)];
}

// ---------------------------------------------------------------- open ---

List<Offset>? _line(List<Offset> pts, double length, double gap, double step) {
  if (gap < length * 0.8) return null;
  var a = pts.first;
  var b = pts.last;
  final dir = (b - a) / gap;
  var maxDev = 0.0;
  for (final p in pts) {
    final rel = p - a;
    maxDev = math.max(maxDev, (rel.dx * dir.dy - rel.dy * dir.dx).abs());
  }
  if (maxDev / gap > 0.07) return null;
  // Nearly level or plumb lines are made exactly so.
  final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
  const snap = 5 * math.pi / 180;
  final fromLevel = (angle.abs()) < snap
      ? angle.abs()
      : (math.pi - angle.abs()) < snap
      ? math.pi - angle.abs()
      : null;
  if (fromLevel != null) {
    final y = (a.dy + b.dy) / 2;
    a = Offset(a.dx, y);
    b = Offset(b.dx, y);
  } else if ((angle.abs() - math.pi / 2).abs() < snap) {
    final x = (a.dx + b.dx) / 2;
    a = Offset(x, a.dy);
    b = Offset(x, b.dy);
  }
  return _densify([a, b], step);
}

List<Offset>? _arrow(List<Offset> pts, double length, double step) {
  final keep = _douglasPeucker(pts, length * 0.04);
  if (keep.length < 3) return null;
  final tipIndex = keep[1];
  final start = pts.first;
  final tip = pts[tipIndex];
  final shaft = (tip - start).distance;
  if (shaft < length * 0.4) return null;
  // The shaft is straight.
  final dir = (tip - start) / shaft;
  for (var i = 0; i <= tipIndex; i++) {
    final rel = pts[i] - start;
    if ((rel.dx * dir.dy - rel.dy * dir.dx).abs() > shaft * 0.08) return null;
  }
  final head = pts.sublist(tipIndex);
  if (head.length < 4) return null;
  final half = head.length ~/ 2;
  Offset farthest(List<Offset> part) =>
      part.reduce((a, b) => (a - tip).distance >= (b - tip).distance ? a : b);
  final c = farthest(head.sublist(0, half));
  final d = farthest(head.sublist(half));
  final cl = (c - tip).distance;
  final dl = (d - tip).distance;
  if (cl < shaft * 0.1 || dl < shaft * 0.1) return null;
  if (cl > shaft * 0.45 || dl > shaft * 0.45) return null;
  final back = (start - tip) / shaft;
  double turn(Offset v) {
    final cross = back.dx * v.dy - back.dy * v.dx;
    final dot = back.dx * v.dx + back.dy * v.dy;
    return math.atan2(cross, dot); // signed angle from the shaft's back
  }

  final tc = turn(c - tip);
  final td = turn(d - tip);
  const lo = 12 * math.pi / 180;
  const hi = 75 * math.pi / 180;
  if (tc.abs() < lo || tc.abs() > hi || td.abs() < lo || td.abs() > hi) {
    return null;
  }
  if (tc.sign == td.sign) return null; // barbs on opposite sides
  final barb = ((cl + dl) / 2).clamp(shaft * 0.12, shaft * 0.3);
  const spread = 30 * math.pi / 180;
  Offset barbEnd(double sign) {
    final a = sign * spread;
    final v = Offset(
      back.dx * math.cos(a) - back.dy * math.sin(a),
      back.dx * math.sin(a) + back.dy * math.cos(a),
    );
    return tip + v * barb;
  }

  return _densify([start, tip, barbEnd(tc.sign), tip, barbEnd(td.sign)], step);
}

// -------------------------------------------------------------- closed ---

List<Offset>? _closedShape(List<Offset> pts, double length, double step) {
  final bounds = _bounds(pts);
  final w = bounds.width;
  final h = bounds.height;
  final longest = math.max(w, h);
  if (longest <= 0 || math.min(w, h) < longest * 0.12) return null;

  final round = _ellipse(pts, bounds, length, step);
  if (round != null) return round;
  return _polygon(pts, length, step);
}

List<Offset>? _ellipse(
  List<Offset> pts,
  Rect bounds,
  double length,
  double step,
) {
  final a = bounds.width / 2;
  final b = bounds.height / 2;
  if (math.min(a, b) < math.max(a, b) * 0.25) return null;
  final c = bounds.center;
  final sample = _resample(pts, 72);
  final rho = [
    for (final p in sample)
      math.sqrt(
        math.pow((p.dx - c.dx) / a, 2) + math.pow((p.dy - c.dy) / b, 2),
      ),
  ];
  final mean = rho.reduce((x, y) => x + y) / rho.length;
  final variance =
      rho.fold<double>(0, (s, r) => s + (r - mean) * (r - mean)) / rho.length;
  if ((mean - 1).abs() > 0.1 || math.sqrt(variance) > 0.085) return null;
  // Roughly one lap, not a scribble.
  final h = (a - b) * (a - b) / ((a + b) * (a + b));
  final perimeter =
      math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h)));
  if (length / perimeter > 1.45 || length / perimeter < 0.7) return null;

  var rx = a;
  var ry = b;
  if (math.max(a, b) / math.min(a, b) < 1.14) {
    rx = ry = (a + b) / 2;
  }
  // Start where the pen did and go the way it went.
  final first = pts.first;
  final phase = math.atan2((first.dy - c.dy) / b, (first.dx - c.dx) / a);
  final dir = _signedArea(pts) >= 0 ? 1.0 : -1.0;
  final n = math.max(48, math.min(160, (perimeter / step).ceil()));
  return [
    for (var i = 0; i <= n; i++)
      Offset(
        c.dx + rx * math.cos(phase + dir * 2 * math.pi * i / n),
        c.dy + ry * math.sin(phase + dir * 2 * math.pi * i / n),
      ),
  ];
}

List<Offset>? _polygon(List<Offset> pts, double length, double step) {
  final path = [...pts, pts.first];
  final keep = _douglasPeucker(path, length * 0.05);
  var v = [for (final i in keep.take(keep.length - 1)) path[i]];

  // Drop shallow bends and tiny edges until only real corners remain.
  bool changed = true;
  while (changed && v.length > 3) {
    changed = false;
    var weakest = -1;
    var weakestTurn = double.infinity;
    for (var i = 0; i < v.length; i++) {
      final t = _turn(v, i).abs();
      final prev = v[(i + v.length - 1) % v.length];
      final tiny = (v[i] - prev).distance < length * 0.08;
      final score = tiny ? 0.0 : t;
      if (score < weakestTurn) {
        weakestTurn = score;
        weakest = i;
      }
    }
    if (weakestTurn < 25 * math.pi / 180) {
      v = [...v]..removeAt(weakest);
      changed = true;
    }
  }
  if (v.length != 3 && v.length != 4) return null;

  var perimeter = 0.0;
  for (var i = 0; i < v.length; i++) {
    perimeter += (v[(i + 1) % v.length] - v[i]).distance;
  }
  if (length / perimeter > 1.4) return null;

  if (v.length == 3) {
    for (var i = 0; i < 3; i++) {
      if ((v[(i + 1) % 3] - v[i]).distance < perimeter * 0.15) return null;
      if (_turn(v, i).abs() < 25 * math.pi / 180) return null;
    }
    return _densify([...v, v.first], step);
  }

  // Four corners: a rectangle only if they are about right angles and the
  // opposite sides match.
  for (var i = 0; i < 4; i++) {
    if ((_turn(v, i).abs() - math.pi / 2).abs() > 28 * math.pi / 180) {
      return null;
    }
  }
  double side(int i) => (v[(i + 1) % 4] - v[i]).distance;
  for (final r in [side(0) / side(2), side(1) / side(3)]) {
    if (r < 0.6 || r > 1.67) return null;
  }
  return _densify([..._rectangle(v), _rectangle(v).first], step);
}

/// A true rectangle through four rough corners: axis-aligned when the
/// edges are within 12° of the axes, otherwise turned to the drawn angle.
List<Offset> _rectangle(List<Offset> v) {
  final e0 = v[1] - v[0];
  final e2 = v[2] - v[3];
  var u = e0 / e0.distance + e2 / e2.distance;
  if (u.distance < 1e-9) u = e0 / e0.distance;
  u = u / u.distance;
  var angle = math.atan2(u.dy, u.dx);
  final nearest = (angle / (math.pi / 2)).roundToDouble() * (math.pi / 2);
  if ((angle - nearest).abs() < 12 * math.pi / 180) angle = nearest;
  u = Offset(math.cos(angle), math.sin(angle));
  final w = Offset(-u.dy, u.dx);
  double minU = double.infinity, maxU = -double.infinity;
  double minW = double.infinity, maxW = -double.infinity;
  for (final p in v) {
    final pu = p.dx * u.dx + p.dy * u.dy;
    final pw = p.dx * w.dx + p.dy * w.dy;
    minU = math.min(minU, pu);
    maxU = math.max(maxU, pu);
    minW = math.min(minW, pw);
    maxW = math.max(maxW, pw);
  }
  Offset at(double pu, double pw) => u * pu + w * pw;
  final corners = [
    at(minU, minW),
    at(maxU, minW),
    at(maxU, maxW),
    at(minU, maxW),
  ];
  // Keep the way round the pen went.
  return _signedArea(corners) * _signedArea(v) >= 0
      ? corners
      : corners.reversed.toList();
}

// -------------------------------------------------------------- helpers ---

double _pathLength(List<Offset> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += (pts[i] - pts[i - 1]).distance;
  }
  return sum;
}

Rect _bounds(List<Offset> pts) {
  var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
  for (final p in pts) {
    l = math.min(l, p.dx);
    r = math.max(r, p.dx);
    t = math.min(t, p.dy);
    b = math.max(b, p.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

double _signedArea(List<Offset> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final q = pts[(i + 1) % pts.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

/// The turn (radians, signed) at corner [i] of a closed polygon.
double _turn(List<Offset> v, int i) {
  final prev = v[(i + v.length - 1) % v.length];
  final next = v[(i + 1) % v.length];
  final a = v[i] - prev;
  final b = next - v[i];
  return math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
}

/// [count] points spaced evenly along the path.
List<Offset> _resample(List<Offset> pts, int count) {
  final total = _pathLength(pts);
  final out = <Offset>[pts.first];
  var travelled = 0.0;
  var next = total / count;
  for (var i = 1; i < pts.length && out.length < count; i++) {
    final seg = (pts[i] - pts[i - 1]).distance;
    while (seg > 0 && travelled + seg >= next && out.length < count) {
      final t = (next - travelled) / seg;
      out.add(Offset.lerp(pts[i - 1], pts[i], t)!);
      next += total / count;
    }
    travelled += seg;
  }
  return out;
}

/// Indices of the points Douglas–Peucker keeps at tolerance [epsilon].
List<int> _douglasPeucker(List<Offset> pts, double epsilon) {
  final keep = <int>{0, pts.length - 1};
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (lo, hi) = stack.removeLast();
    var far = -1;
    var farDist = epsilon;
    for (var i = lo + 1; i < hi; i++) {
      final d = _distanceToSegment(pts[i], pts[lo], pts[hi]);
      if (d > farDist) {
        farDist = d;
        far = i;
      }
    }
    if (far >= 0) {
      keep.add(far);
      stack
        ..add((lo, far))
        ..add((far, hi));
    }
  }
  return keep.toList()..sort();
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Points along the polyline through [verts], at most [step] apart.
List<Offset> _densify(List<Offset> verts, double step) {
  final out = <Offset>[verts.first];
  for (var i = 1; i < verts.length; i++) {
    final a = verts[i - 1];
    final b = verts[i];
    final n = math.max(1, math.min(200, ((b - a).distance / step).ceil()));
    for (var k = 1; k <= n; k++) {
      out.add(Offset.lerp(a, b, k / n)!);
    }
  }
  return out;
}
