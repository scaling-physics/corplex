import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';

void main() {
  late Sketch sketch;
  late InkInputPolicy policy;
  late int gestures;

  Widget host({bool erasing = false}) => MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 400,
          child: InkCanvas(
            sketch: sketch,
            policy: policy,
            tool: InkTool.pen,
            color: const Color(0xFF000000),
            width: 0.007,
            erasing: erasing,
            onGestureStart: () => gestures++,
            onChanged: (s) => setState(() => sketch = s),
          ),
        ),
      ),
    ),
  );

  setUp(() {
    sketch = const Sketch();
    policy = InkInputPolicy();
    gestures = 0;
  });

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset to, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final origin = tester.getTopLeft(find.byType(InkCanvas));
    final g = await tester.startGesture(origin + from, kind: kind);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(origin + Offset.lerp(from, to, i / 10)!);
    }
    await g.up();
    await tester.pump();
  }

  testWidgets('a pen stroke is recorded in canvas-width units', (tester) async {
    await tester.pumpWidget(host());
    await drag(tester, const Offset(40, 40), const Offset(360, 40));

    expect(sketch.strokes, hasLength(1));
    final points = sketch.strokes.single.points;
    expect(points.first.x, closeTo(0.1, 0.001));
    expect(points.last.x, closeTo(0.9, 0.001));
    expect(points.first.y, closeTo(0.1, 0.001));
    expect(gestures, 1);
  });

  testWidgets('after a stylus, a resting palm draws nothing', (tester) async {
    await tester.pumpWidget(host());
    await drag(tester, const Offset(40, 40), const Offset(200, 40));
    await drag(
      tester,
      const Offset(40, 150),
      const Offset(200, 150),
      kind: PointerDeviceKind.touch,
    );
    expect(sketch.strokes, hasLength(1));
  });

  testWidgets('drawing near the bottom grows the page', (tester) async {
    await tester.pumpWidget(host());
    final height = 400 * Sketch.defaultAspect;
    await drag(tester, Offset(40, height - 10), Offset(300, height - 10));
    expect(sketch.aspect, greaterThan(Sketch.defaultAspect));
  });

  testWidgets('one eraser swipe removes crossed strokes as one gesture', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await drag(tester, const Offset(40, 40), const Offset(360, 40));
    await drag(tester, const Offset(40, 120), const Offset(360, 120));
    await drag(tester, const Offset(40, 200), const Offset(360, 200));
    gestures = 0;

    await tester.pumpWidget(host(erasing: true));
    await drag(tester, const Offset(200, 20), const Offset(200, 140));

    expect(sketch.strokes, hasLength(1));
    expect(sketch.strokes.single.points.first.y, closeTo(0.5, 0.01));
    expect(gestures, 1);
  });

  testWidgets(
    'a hovering pen shows a ring, which goes when it leaves or touches down',
    (tester) async {
      await tester.pumpWidget(host());
      final origin = tester.getTopLeft(find.byType(InkCanvas));
      expect(find.byKey(const ValueKey('ink-hover')), findsNothing);

      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.addPointer(location: origin + const Offset(100, 100));
      await pen.moveTo(origin + const Offset(120, 110));
      await tester.pump();
      expect(find.byKey(const ValueKey('ink-hover')), findsOneWidget);

      await pen.moveTo(const Offset(-50, -50)); // out of the canvas
      await tester.pump();
      expect(find.byKey(const ValueKey('ink-hover')), findsNothing);

      // A finger or mouse hovering doesn't get a pen ring.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: origin + const Offset(50, 50));
      await mouse.moveTo(origin + const Offset(60, 60));
      await tester.pump();
      expect(find.byKey(const ValueKey('ink-hover')), findsNothing);
    },
  );

  test('the pen barrel button erases, like the eraser end', () {
    final p = InkInputPolicy();
    expect(
      p.actionFor(PointerDeviceKind.stylus, eraserTool: false),
      InkAction.draw,
    );
    expect(
      p.actionFor(
        PointerDeviceKind.stylus,
        eraserTool: false,
        stylusButton: true,
      ),
      InkAction.erase,
    );
    expect(
      p.actionFor(
        PointerDeviceKind.touch,
        eraserTool: false,
        stylusButton: true,
      ),
      InkAction.ignore,
      reason: 'the button only means something on a stylus (fingers scroll after a pen)',
    );
  });

  testWidgets('holding the barrel button while dragging erases strokes', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await drag(tester, const Offset(40, 40), const Offset(360, 40));
    expect(sketch.strokes, hasLength(1));

    final origin = tester.getTopLeft(find.byType(InkCanvas));
    final g = await tester.startGesture(
      origin + const Offset(200, 40),
      kind: PointerDeviceKind.stylus,
      buttons: kSecondaryStylusButton,
    );
    await g.moveTo(origin + const Offset(210, 40));
    await g.up();
    await tester.pump();
    expect(sketch.strokes, isEmpty);
  });
}
