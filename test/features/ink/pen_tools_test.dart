import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corplex/app.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/features/audio/audio_playback.dart';
import 'package:corplex/features/ink/handwriting.dart';
import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/ink_session.dart';
import 'package:corplex/features/ink/ink_tools.dart';
import 'package:corplex/features/ocr/ocr_engine.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';

String _sketchOp(Sketch s) => jsonEncode({
  'insert': {'sketch': s.encode()},
});

InkStroke _line(double x0, double y0, double x1, double y1) => InkStroke(
  tool: InkTool.pen,
  color: penInks[0],
  width: 0.007,
  points: [
    for (var i = 0; i <= 6; i++)
      InkPoint(x0 + (x1 - x0) * i / 6, y0 + (y1 - y0) * i / 6, 0.5),
  ],
);

class _FakeOcr implements OcrEngine {
  _FakeOcr(this.lines);
  List<String> lines;
  int calls = 0;

  @override
  Future<OcrPageText> recognize(Uint8List png) async {
    calls++;
    return OcrPageText([for (final l in lines) OcrLine(l, const [])]);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    inkPolicy
      ..stylusSeen = false
      ..fingerDrawsOverride = null;
    inkClipboard = const [];
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> openNote(
    WidgetTester tester,
    String content, {
    OcrEngine? ocr,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3; // a 400×800 phone
    addTearDown(tester.view.reset);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Ink'),
            content: Value(content),
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          shareIntentSourceProvider.overrideWithValue(
            const NoShareIntentSource(),
          ),
          if (ocr != null) inkOcrEngineProvider.overrideWithValue(ocr),
        ],
        child: const CorplexApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ink'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  QuillController controller(WidgetTester tester) =>
      tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

  List<Sketch> sketches(WidgetTester tester) => [
    for (final op in controller(tester).document.toDelta().toList())
      if (op.data case {'sketch': final String data}) Sketch.decode(data),
  ];

  List<Sketch> shown(WidgetTester tester) => [
    for (final c in tester.widgetList<InkCanvas>(find.byType(InkCanvas)))
      c.sketch,
  ];

  String text(WidgetTester tester) =>
      controller(tester).document.toPlainText().replaceAll('￼', '#');

  InkSession session(WidgetTester tester) =>
      InkSessionScope.maybeOf(tester.element(find.byType(InkCanvas)))!;

  /// Moves a pen through [path], optionally holding still at the end for
  /// [hold] before lifting.
  Future<void> stroke(
    WidgetTester tester,
    List<Offset> path, {
    Duration? hold,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await tester.startGesture(path.first, kind: kind);
    for (final p in path.skip(1)) {
      await g.moveTo(p);
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (hold != null) await tester.pump(hold);
    await g.up();
    await tester.pumpAndSettle();
  }

  List<Offset> through(List<Offset> corners, {int per = 8}) => [
    for (var i = 1; i < corners.length; i++)
      for (var k = 0; k < per; k++)
        Offset.lerp(corners[i - 1], corners[i], k / per)!,
    corners.last,
  ];

  final emptyDrawing =
      '[{"insert":"Before\\n"},${_sketchOp(const Sketch(aspect: 0.8))},'
      '{"insert":"\\nAfter\\n"}]';

  group('shapes snap', () {
    testWidgets('a rectangle held at the end becomes a clean one', (
      tester,
    ) async {
      await openNote(tester, emptyDrawing);
      final r = tester.getRect(find.byType(InkCanvas));
      final o = r.topLeft + const Offset(60, 40);
      await stroke(
        tester,
        through([
          o,
          o + const Offset(150, 3),
          o + const Offset(148, 100),
          o + const Offset(2, 98),
          o + const Offset(3, 4),
        ]),
        hold: const Duration(milliseconds: 600),
      );
      final points = shown(tester).single.strokes.single.points;
      expect(
        sketches(tester).single.strokes.single.points,
        hasLength(points.length),
      );
      final xs = points.map((p) => p.x), ys = points.map((p) => p.y);
      final left = xs.reduce(math.min), right = xs.reduce(math.max);
      final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
      // Every point is on the box: straight sides and exact corners.
      for (final p in points) {
        final onEdge =
            (p.x - left).abs() < 1e-3 ||
            (p.x - right).abs() < 1e-3 ||
            (p.y - top).abs() < 1e-3 ||
            (p.y - bottom).abs() < 1e-3;
        expect(onEdge, isTrue);
      }
      expect((right - left) * r.width, closeTo(148, 8));
      await dispose(tester);
    });

    testWidgets('without the hold, the stroke is left as drawn', (
      tester,
    ) async {
      await openNote(tester, emptyDrawing);
      final o = tester.getRect(find.byType(InkCanvas)).topLeft;
      final path = through([
        o + const Offset(40, 40),
        o + const Offset(200, 52),
      ], per: 6);
      await stroke(tester, path);
      final pts = shown(tester).single.strokes.single.points;
      // Wobbly input stays wobbly: no dense replacement.
      expect(pts.length, lessThan(15));
      await dispose(tester);
    });

    testWidgets('a held scribble is not snapped', (tester) async {
      await openNote(tester, emptyDrawing);
      final o = tester.getRect(find.byType(InkCanvas)).topLeft;
      final path = through([
        o + const Offset(40, 40),
        o + const Offset(100, 100),
        o + const Offset(60, 40),
        o + const Offset(120, 100),
        o + const Offset(80, 40),
        o + const Offset(140, 100),
      ], per: 6);
      await stroke(tester, path, hold: const Duration(milliseconds: 700));
      final pts = shown(tester).single.strokes.single.points;
      expect(pts.length, lessThanOrEqualTo(path.length));
      await dispose(tester);
    });

    testWidgets('a held line from a pen on the text makes a clean line in '
        'a new drawing', (tester) async {
      await openNote(tester, '[{"insert":"First line\\nSecond line\\n"}]');
      final c = tester.getCenter(
        find.textContaining('First line', findRichText: true),
      );
      await stroke(
        tester,
        through([
          c + const Offset(-60, 0),
          c + const Offset(0, 4),
          c + const Offset(70, -1),
        ], per: 8),
        hold: const Duration(milliseconds: 600),
      );
      expect(text(tester), 'First line\n#\nSecond line\n');
      final pts = sketches(tester).single.strokes.single.points;
      expect(pts.length, greaterThan(15));
      // Straight: the same y all along.
      expect(pts.map((p) => p.y).toSet().length, 1);
      expect(shown(tester).single.strokes, hasLength(1));
      await dispose(tester);
    });
  });

  group('lasso', () {
    // Two strokes on the left, one on the right.
    final drawing = Sketch(
      aspect: 0.8,
      strokes: [
        _line(0.1, 0.1, 0.3, 0.1),
        _line(0.1, 0.2, 0.3, 0.2),
        _line(0.7, 0.15, 0.9, 0.15),
      ],
    );
    final content =
        '[{"insert":"Before\\n"},${_sketchOp(drawing)},{"insert":"\\nAfter\\n"}]';

    Offset at(WidgetTester tester, double x, double y) {
      final r = tester.getRect(find.byType(InkCanvas));
      return r.topLeft + Offset(x * r.width, y * r.width);
    }

    Future<void> select(WidgetTester tester) async {
      await tester.tap(find.byType(InkCanvas));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      await stroke(tester, [
        at(tester, 0.05, 0.05),
        at(tester, 0.4, 0.05),
        at(tester, 0.4, 0.27),
        at(tester, 0.05, 0.27),
        at(tester, 0.05, 0.06),
      ]);
    }

    testWidgets('a loop selects the strokes inside and drags them', (
      tester,
    ) async {
      await openNote(tester, content);
      await select(tester);
      expect(find.byKey(const ValueKey('ink-selection')), findsOneWidget);
      expect(find.byKey(const ValueKey('ink-selection-menu')), findsOneWidget);
      // Selecting changes nothing.
      expect(sketches(tester).single.strokes, hasLength(3));

      final width = tester.getRect(find.byType(InkCanvas)).width;
      await stroke(tester, [
        at(tester, 0.2, 0.1),
        at(tester, 0.2, 0.1) + const Offset(20, 10),
        at(tester, 0.2, 0.1) + const Offset(40, 20),
      ]);
      final moved = shown(tester).single.strokes;
      expect(moved, hasLength(3));
      expect(moved[0].points.first.x, closeTo(0.1 + 40 / width, 0.005));
      expect(moved[0].points.first.y, closeTo(0.1 + 20 / width, 0.005));
      expect(moved[1].points.first.x, closeTo(0.1 + 40 / width, 0.005));
      // The one outside the loop stayed.
      expect(moved[2].points.first.x, closeTo(0.7, 1e-6));
      // Saved the same way, in one edit: undo puts it back.
      expect(
        sketches(tester).single.strokes[0].points.first.x,
        closeTo(0.1 + 40 / width, 0.005),
      );
      controller(tester).undo();
      await tester.pumpAndSettle();
      expect(
        sketches(tester).single.strokes[0].points.first.x,
        closeTo(0.1, 1e-3),
      );
      expect(
        shown(tester).single.strokes[0].points.first.x,
        closeTo(0.1, 1e-3),
      );
      await dispose(tester);
    });

    testWidgets('delete, duplicate and colour act on the selection', (
      tester,
    ) async {
      await openNote(tester, content);
      await select(tester);

      await tester.tap(find.byKey(const ValueKey('ink-sel-duplicate')));
      await tester.pumpAndSettle();
      expect(shown(tester).single.strokes, hasLength(5));
      expect(sketches(tester).single.strokes, hasLength(5));
      // The copies are the selection now.
      expect(find.byKey(const ValueKey('ink-selection-menu')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ink-sel-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clay'));
      await tester.pumpAndSettle();
      final colors = shown(tester).single.strokes.map((s) => s.color).toList();
      expect(colors.sublist(3), everyElement(penInks[2]));
      expect(colors.sublist(0, 3), everyElement(penInks[0]));

      await tester.tap(find.byKey(const ValueKey('ink-sel-delete')));
      await tester.pumpAndSettle();
      expect(shown(tester).single.strokes, hasLength(3));
      expect(sketches(tester).single.strokes, hasLength(3));
      expect(find.byKey(const ValueKey('ink-selection-menu')), findsNothing);
      await dispose(tester);
    });

    testWidgets('tapping outside clears; copy then paste adds the strokes', (
      tester,
    ) async {
      await openNote(tester, content);
      await select(tester);
      await tester.tap(find.byKey(const ValueKey('ink-sel-copy')));
      await tester.pumpAndSettle();
      expect(inkClipboard, hasLength(2));

      final tap = await tester.startGesture(
        at(tester, 0.6, 0.6),
        kind: PointerDeviceKind.stylus,
      );
      await tap.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ink-selection-menu')), findsNothing);
      expect(sketches(tester).single.strokes, hasLength(3));

      await tester.tap(find.byKey(const ValueKey('ink-paste')));
      await tester.pumpAndSettle();
      expect(shown(tester).single.strokes, hasLength(5));
      await dispose(tester);
    });

    testWidgets('a loop around too little selects nothing', (tester) async {
      await openNote(tester, content);
      await tester.tap(find.byType(InkCanvas));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select'));
      await tester.pumpAndSettle();
      // Covers only the left end of the first line.
      await stroke(tester, [
        at(tester, 0.05, 0.05),
        at(tester, 0.15, 0.05),
        at(tester, 0.15, 0.13),
        at(tester, 0.05, 0.13),
        at(tester, 0.05, 0.06),
      ]);
      expect(find.byKey(const ValueKey('ink-selection-menu')), findsNothing);
      await dispose(tester);
    });
  });

  group('handwriting', () {
    testWidgets('a drawing is read when the pen goes idle, and changing the '
        'strokes clears the text', (tester) async {
      final ocr = _FakeOcr(['Hello', 'world']);
      await openNote(tester, emptyDrawing, ocr: ocr);
      session(tester).renderForOcr = (_) async => Uint8List(4);
      final o = tester.getRect(find.byType(InkCanvas)).topLeft;
      await stroke(
        tester,
        through([o + const Offset(40, 40), o + const Offset(150, 60)]),
      );
      expect(ocr.calls, 0); // not yet: the pen has only just lifted
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(ocr.calls, 1);
      expect(sketches(tester).single.text, 'Hello\nworld');
      expect(sketches(tester).single.strokes, hasLength(1));

      // Reading it was not an undo step: undo takes back the stroke.
      ocr.lines = ['Hello again'];
      await stroke(
        tester,
        through([o + const Offset(40, 90), o + const Offset(150, 100)]),
      );
      // New strokes: the old text no longer applies.
      expect(sketches(tester).single.text, isNull);
      expect(shown(tester).single.text, isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(sketches(tester).single.text, 'Hello again');

      controller(tester).undo();
      await tester.pumpAndSettle();
      // (Quill merges edits made within 400 ms of wall-clock time, so
      // both strokes may go; what matters is that the text isn't a
      // step of its own.)
      expect(sketches(tester).single.strokes.length, lessThan(2));
      await dispose(tester);
    });

    testWidgets('no handwriting found leaves the drawing alone', (
      tester,
    ) async {
      final ocr = _FakeOcr([]);
      await openNote(tester, emptyDrawing, ocr: ocr);
      session(tester).renderForOcr = (_) async => Uint8List(4);
      final o = tester.getRect(find.byType(InkCanvas)).topLeft;
      await stroke(
        tester,
        through([o + const Offset(40, 40), o + const Offset(150, 60)]),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(ocr.calls, 1);
      expect(sketches(tester).single.text, isNull);
      // Not asked again and again.
      await tester.pump(const Duration(seconds: 6));
      expect(ocr.calls, 1);
      await dispose(tester);
    });

    testWidgets('putting the drawing away reads it at once', (tester) async {
      final ocr = _FakeOcr(['Notes']);
      await openNote(tester, emptyDrawing, ocr: ocr);
      session(tester).renderForOcr = (_) async => Uint8List(4);
      final o = tester.getRect(find.byType(InkCanvas)).topLeft;
      await stroke(
        tester,
        through([o + const Offset(40, 40), o + const Offset(150, 60)]),
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump();
      expect(sketches(tester).single.text, 'Notes');
      await tester.pump(const Duration(seconds: 3));
      await dispose(tester);
    });

    testWidgets('Convert to text replaces the drawing with its text, one '
        'undoable edit', (tester) async {
      final drawn = Sketch(
        aspect: 0.4,
        strokes: [_line(0.1, 0.1, 0.5, 0.1)],
        text: 'Meeting\nnotes',
      );
      await openNote(
        tester,
        '[{"insert":"Before\\n"},${_sketchOp(drawn)},{"insert":"\\nAfter\\n"}]',
        ocr: _FakeOcr(['unused']),
      );
      await tester.tap(find.byType(InkCanvas));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More drawing options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert to text'));
      await tester.pumpAndSettle();
      expect(sketches(tester), isEmpty);
      expect(find.byType(InkCanvas), findsNothing);
      expect(text(tester), 'Before\nMeeting\nnotes\nAfter\n');
      expect(find.byKey(const ValueKey('inline-ink-toolbar')), findsNothing);

      controller(tester).undo();
      await tester.pumpAndSettle();
      expect(sketches(tester), hasLength(1));
      expect(text(tester), 'Before\n#\nAfter\n');
      await dispose(tester);
    });

    testWidgets('Convert to text reads the drawing first when it has no '
        'text yet', (tester) async {
      final ocr = _FakeOcr(['Read now']);
      await openNote(
        tester,
        '[{"insert":"Before\\n"},'
        '${_sketchOp(Sketch(aspect: 0.4, strokes: [_line(0.1, 0.1, 0.5, 0.1)]))},'
        '{"insert":"\\nAfter\\n"}]',
        ocr: ocr,
      );
      session(tester).renderForOcr = (_) async => Uint8List(4);
      await tester.tap(find.byType(InkCanvas));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More drawing options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Convert to text'));
      await tester.pumpAndSettle();
      expect(text(tester), 'Before\nRead now\nAfter\n');
      await dispose(tester);
    });

    testWidgets('without a reader there is no Convert to text', (tester) async {
      await openNote(tester, emptyDrawing);
      await tester.tap(find.byType(InkCanvas));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More drawing options'));
      await tester.pumpAndSettle();
      expect(find.text('Expand'), findsOneWidget);
      expect(find.text('Convert to text'), findsNothing);
      await dispose(tester);
    });
  });
}
