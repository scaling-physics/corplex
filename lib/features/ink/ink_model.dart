import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// The kind of mark a stroke makes.
enum InkTool { pen, highlighter }

/// One continuous mark. Coordinates are in *canvas-width units*: x runs
/// 0..1 across the canvas and y uses the same scale (so a square stays a
/// square), which lets a sketch drawn on a phone render identically on an
/// iPad. Each point carries normalized pen pressure (0..1).
class InkStroke {
  const InkStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  factory InkStroke.fromJson(Map<String, Object?> json) {
    final flat = (json['p']! as List).cast<num>();
    return InkStroke(
      tool: json['t'] == 'h' ? InkTool.highlighter : InkTool.pen,
      color: Color(int.parse(json['c']! as String, radix: 16)),
      width: (json['w']! as num).toDouble(),
      points: [
        for (var i = 0; i + 2 < flat.length; i += 3)
          InkPoint(
            flat[i].toDouble(),
            flat[i + 1].toDouble(),
            flat[i + 2].toDouble(),
          ),
      ],
    );
  }

  final InkTool tool;
  final Color color;

  /// Base line width, in canvas-width units.
  final double width;
  final List<InkPoint> points;

  /// Compact form: points flattened to `[x, y, p, x, y, p, …]`, rounded to
  /// 4 decimals (sub-pixel even on a 12.9" iPad), since notes sync.
  Map<String, Object?> toJson() => {
    't': tool == InkTool.highlighter ? 'h' : 'p',
    'c': color.toARGB32().toRadixString(16).padLeft(8, '0'),
    'w': _round(width),
    'p': [
      for (final pt in points) ...[_round(pt.x), _round(pt.y), _round(pt.p)],
    ],
  };

  /// Whether this stroke passes within [radius] of [at] — used by the
  /// eraser, which removes whole strokes (like Apple Notes' object eraser).
  bool hits(Offset at, double radius) {
    final reach = radius + width;
    if (points.length == 1) {
      return (points.single.offset - at).distance <= reach;
    }
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(at, points[i - 1].offset, points[i].offset) <=
          reach) {
        return true;
      }
    }
    return false;
  }

  InkStroke copyWith({Color? color, List<InkPoint>? points}) => InkStroke(
    tool: tool,
    color: color ?? this.color,
    width: width,
    points: points ?? this.points,
  );

  /// This stroke moved by [by] (canvas-width units).
  InkStroke translated(Offset by) => copyWith(
    points: [for (final p in points) InkPoint(p.x + by.dx, p.y + by.dy, p.p)],
  );

  /// The box around the stroke's points, grown by half its width.
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var l = points.first.x, r = l, t = points.first.y, b = t;
    for (final p in points) {
      l = math.min(l, p.x);
      r = math.max(r, p.x);
      t = math.min(t, p.y);
      b = math.max(b, p.y);
    }
    return Rect.fromLTRB(l, t, r, b).inflate(width / 2);
  }

  /// Lowest point reached, so the canvas can grow to fit.
  double get bottom => points.fold(0, (m, p) => math.max(m, p.y));

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }
}

class InkPoint {
  const InkPoint(this.x, this.y, this.p);

  final double x;
  final double y;
  final double p;

  Offset get offset => Offset(x, y);
}

/// A drawing embedded in a note: its strokes plus its height as a fraction
/// of its width (the canvas grows downward as you draw near the bottom),
/// and the handwriting recognised in it ([text], derived on the device;
/// null until recognised or after the strokes change).
class Sketch {
  const Sketch({
    this.strokes = const [],
    this.aspect = defaultAspect,
    this.text,
  });

  factory Sketch.decode(String data) {
    try {
      final json = jsonDecode(data) as Map<String, Object?>;
      return Sketch(
        aspect: (json['a'] as num?)?.toDouble() ?? defaultAspect,
        text: json['t'] as String?,
        strokes: [
          for (final s in (json['s'] as List? ?? const []))
            InkStroke.fromJson((s as Map).cast<String, Object?>()),
        ],
      );
    } catch (_) {
      // A damaged sketch shouldn't break the whole note.
      return const Sketch();
    }
  }

  static const defaultAspect = 0.6;
  static const maxAspect = 4.0;

  final List<InkStroke> strokes;
  final double aspect;

  /// Recognised handwriting, kept in the note (key `t`) so search, export
  /// and other devices see it without recognising again.
  final String? text;

  bool get isEmpty => strokes.isEmpty;

  String encode() => jsonEncode({
    'v': 1,
    'a': InkStroke._round(aspect),
    's': [for (final s in strokes) s.toJson()],
    if (text case final t? when t.isNotEmpty) 't': t,
  });

  /// A copy. Changing [strokes] drops the recognised [text] (it no longer
  /// matches) unless a new one is given.
  Sketch copyWith({List<InkStroke>? strokes, double? aspect, String? text}) =>
      Sketch(
        strokes: strokes ?? this.strokes,
        aspect: aspect ?? this.aspect,
        text: text ?? (strokes == null ? this.text : null),
      );
}

/// Pen pressure normalized to 0..1. Fingers and mice report a fixed or
/// zero pressure; they get a neutral mid value so lines look even.
double normalizePressure(double pressure, double min, double max) {
  if (max <= min) return 0.5;
  return ((pressure - min) / (max - min)).clamp(0.0, 1.0);
}
