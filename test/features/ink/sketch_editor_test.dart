import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/pencil_taps.dart';
import 'package:corplex/features/ink/sketch_editor_screen.dart';

void main() {
  bool selected(WidgetTester tester, String tooltip) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, _icon(tooltip)))
      .isSelected!;

  // The tap arrives through a stream, i.e. a microtask; a second pump
  // builds the frame it scheduled.
  Future<void> tap(WidgetTester tester, PencilAction action) async {
    PencilTaps.instance.debugTap(action);
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SketchEditorScreen(initial: const Sketch())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Pencil double-tap follows the iPadOS preference', (
    tester,
  ) async {
    await open(tester);
    expect(selected(tester, 'Pen'), isTrue);

    await tap(tester, PencilAction.switchEraser);
    expect(selected(tester, 'Eraser'), isTrue);

    // Tapping again goes back to what was in use.
    await tap(tester, PencilAction.switchEraser);
    expect(selected(tester, 'Pen'), isTrue);

    await tap(tester, PencilAction.ignore);
    expect(selected(tester, 'Pen'), isTrue);

    await tap(tester, PencilAction.switchPrevious);
    expect(selected(tester, 'Eraser'), isTrue);
  });

  test('an unknown preference from the platform falls back to the eraser', () {
    expect(PencilTaps.parse('showColorPalette'), PencilAction.showColorPalette);
    expect(PencilTaps.parse('something new'), PencilAction.switchEraser);
    expect(PencilTaps.parse(null), PencilAction.switchEraser);
  });

  testWidgets('Ctrl/Cmd+Z undoes a stroke and Shift+Z redoes it', (
    tester,
  ) async {
    await open(tester);
    final canvas = find.byType(InkCanvas);
    final origin = tester.getTopLeft(canvas);
    final g = await tester.startGesture(
      origin + const Offset(40, 40),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(origin + Offset(40.0 + i * 20, 40));
    }
    await g.up();
    await tester.pump();
    int strokes() => tester.widget<InkCanvas>(canvas).sketch.strokes.length;
    expect(strokes(), 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(strokes(), 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(strokes(), 1);
  });
}

IconData _icon(String tooltip) => switch (tooltip) {
  'Pen' => Icons.edit_outlined,
  'Eraser' => Icons.cleaning_services_outlined,
  _ => throw ArgumentError(tooltip),
};
