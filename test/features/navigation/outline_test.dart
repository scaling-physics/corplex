import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/navigation/outline_overlay.dart';
import 'package:corplex/features/navigation/outline_pinch.dart';
import 'package:corplex/features/notes/note_sections.dart';
import 'package:corplex/theme/app_theme.dart';

import '../../support/mac_screenshot.dart';

void main() {
  const headings = [
    NoteHeading('Intro', 1, 0),
    NoteHeading('Methods', 2, 40),
    NoteHeading('Results', 1, 90),
  ];

  setUpAll(loadMacFonts);

  test('the current section is the last heading before the caret', () {
    expect(currentHeadingIndex(headings, 0), 0);
    expect(currentHeadingIndex(headings, 50), 1);
    expect(currentHeadingIndex(headings, 500), 2);
    expect(currentHeadingIndex(const [NoteHeading('A', 1, 10)], 3), -1);
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('tap jumps, Return jumps to the selection, Escape closes', (
    tester,
  ) async {
    NoteHeading? picked;
    var closed = 0;
    await tester.pumpWidget(
      host(
        OutlineOverlay(
          headings: headings,
          current: 1,
          onPick: (h) => picked = h,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Methods'), findsOneWidget);

    await tester.tap(find.text('Results'));
    expect(picked?.text, 'Results');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked?.text, 'Results');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked?.text, 'Methods');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 1);
    await tester.tapAt(const Offset(5, 5));
    expect(closed, 2);
  }, variant: macOnly);

  testWidgets('a note without headings says so', (tester) async {
    await tester.pumpWidget(
      host(
        OutlineOverlay(
          headings: const [],
          current: -1,
          onPick: (_) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No headings in this note yet'), findsOneWidget);
  });

  testWidgets('trackpad pinch out and in fire once per gesture', (
    tester,
  ) async {
    var out = 0;
    var inn = 0;
    await tester.pumpWidget(
      host(
        PinchDetector(
          onPinchOut: () => out++,
          onPinchIn: () => inn++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(PinchDetector));
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, scale: 0.9);
    expect(out, 0, reason: 'not far enough');
    await pad.panZoomUpdate(center, scale: 0.7);
    await pad.panZoomUpdate(center, scale: 0.6);
    expect(out, 1);
    await pad.panZoomEnd();

    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, scale: 1.4);
    expect(inn, 1);
    expect(out, 1);
    await pad.panZoomEnd();
  });

  testWidgets('a plain two-finger scroll is not a pinch', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      host(
        PinchDetector(
          onPinchOut: () => fired++,
          onPinchIn: () => fired++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(PinchDetector));
    final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pad.panZoomStart(center);
    await pad.panZoomUpdate(center, pan: const Offset(0, -80));
    await pad.panZoomEnd();
    expect(fired, 0);
  });
}
