import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/sketch_embed.dart';

InkStroke _line(double y) => InkStroke(
  tool: InkTool.pen,
  color: const Color(0xFF2B2F2B),
  width: 0.007,
  points: [InkPoint(0.1, y, 0.3), InkPoint(0.5, y, 0.8), InkPoint(0.9, y, 1)],
);

void main() {
  group('Sketch', () {
    test('encodes compactly and decodes to the same drawing', () {
      final sketch = Sketch(
        aspect: 1.25,
        strokes: [
          _line(0.2),
          InkStroke(
            tool: InkTool.highlighter,
            color: const Color(0xFFF2D66B),
            width: 0.03,
            points: const [InkPoint(0.123456789, 0.5, 0.5)],
          ),
        ],
      );
      final decoded = Sketch.decode(sketch.encode());
      expect(decoded.aspect, 1.25);
      expect(decoded.strokes, hasLength(2));
      expect(decoded.strokes[0].points.map((p) => p.p), [0.3, 0.8, 1]);
      expect(decoded.strokes[1].tool, InkTool.highlighter);
      expect(decoded.strokes[1].color, const Color(0xFFF2D66B));
      expect(decoded.strokes[1].points.single.x, 0.1235, reason: 'rounded');
    });

    test('damaged data yields an empty sketch instead of throwing', () {
      expect(Sketch.decode('not json').isEmpty, isTrue);
      expect(Sketch.decode('{"s":[{"t":"p"}]}').isEmpty, isTrue);
    });
  });

  test('hits: near a segment, not far from it', () {
    final stroke = _line(0.5);
    expect(stroke.hits(const Offset(0.3, 0.51), 0.02), isTrue);
    expect(stroke.hits(const Offset(0.3, 0.7), 0.02), isFalse);
    expect(stroke.hits(const Offset(0.95, 0.5), 0.02), isFalse);
  });

  test('pressure normalization', () {
    expect(normalizePressure(0.5, 0, 1), 0.5);
    expect(normalizePressure(4, 0, 4), 1);
    expect(normalizePressure(1, 1, 1), 0.5, reason: 'no pressure range');
    expect(normalizePressure(9, 0, 4), 1);
  });

  group('palm rejection', () {
    test('fingers draw until a stylus is seen, then they are ignored', () {
      final policy = InkInputPolicy();
      expect(
        policy.actionFor(PointerDeviceKind.touch, eraserTool: false),
        InkAction.draw,
      );
      expect(
        policy.actionFor(PointerDeviceKind.stylus, eraserTool: false),
        InkAction.draw,
      );
      expect(
        policy.actionFor(PointerDeviceKind.touch, eraserTool: false),
        InkAction.ignore,
      );
    });

    test('the user can turn finger drawing back on', () {
      final policy = InkInputPolicy()..stylusSeen = true;
      policy.fingerDrawsOverride = true;
      expect(
        policy.actionFor(PointerDeviceKind.touch, eraserTool: false),
        InkAction.draw,
      );
    });

    test("the stylus's eraser end always erases", () {
      final policy = InkInputPolicy();
      expect(
        policy.actionFor(PointerDeviceKind.invertedStylus, eraserTool: false),
        InkAction.erase,
      );
      expect(
        policy.actionFor(PointerDeviceKind.stylus, eraserTool: true),
        InkAction.erase,
      );
    });
  });

  test('the constant empty sketch matches the encoder', () {
    expect(emptySketchData, const Sketch().encode());
  });
}
