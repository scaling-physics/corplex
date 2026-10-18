import 'dart:convert';

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
import 'package:corplex/features/ink/ink_canvas.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/ink/sketch_editor_screen.dart';
import 'package:corplex/features/share/share_import.dart';

import '../../support/fake_audio_engine.dart';

String _sketchOp(Sketch s) => jsonEncode({
  'insert': {'sketch': s.encode()},
});

const _stroke = InkStroke(
  tool: InkTool.pen,
  color: Color(0xFF2B2F2B),
  width: 0.007,
  points: [InkPoint(0.1, 0.1, 0.5), InkPoint(0.5, 0.2, 0.5)],
);

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EditableText.debugDeterministicCursor = true;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    // The policy is app-wide; each test starts as if no pen was seen yet.
    inkPolicy
      ..stylusSeen = false
      ..fingerDrawsOverride = null;
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    db.close();
  });

  Future<void> openNote(WidgetTester tester, String content) async {
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

  /// The drawings in the open note, in order.
  List<Sketch> sketches(WidgetTester tester) => [
    for (final op in controller(tester).document.toDelta().toList())
      if (op.data case {'sketch': final String data}) Sketch.decode(data),
  ];

  /// The drawings as the screen shows them (not just as saved).
  List<Sketch> shown(WidgetTester tester) => [
    for (final c in tester.widgetList<InkCanvas>(find.byType(InkCanvas)))
      c.sketch,
  ];

  String text(WidgetTester tester) =>
      controller(tester).document.toPlainText().replaceAll('￼', '#');

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset by, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await tester.startGesture(from, kind: kind);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(from + by * (i / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  final toolbar = find.byKey(const ValueKey('inline-ink-toolbar'));

  testWidgets('a pen draws on a drawing where it is, no other screen', (
    tester,
  ) async {
    await openNote(
      tester,
      '[{"insert":"Before\\n"},${_sketchOp(const Sketch(aspect: 0.4))},'
      '{"insert":"\\nAfter\\n"}]',
    );
    final canvas = find.byType(InkCanvas);
    await drag(
      tester,
      tester.getTopLeft(canvas) + const Offset(40, 30),
      const Offset(200, 40),
    );
    expect(find.byType(SketchEditorScreen), findsNothing);
    expect(sketches(tester).single.strokes, hasLength(1));
    expect(shown(tester).single.strokes, hasLength(1));
    expect(text(tester), 'Before\n#\nAfter\n');
    // The tools show while drawing.
    expect(toolbar, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a finger scrolls past a drawing until it is chosen', (
    tester,
  ) async {
    await openNote(
      tester,
      '[{"insert":"Before\\n"},${_sketchOp(const Sketch(aspect: 0.4))},'
      '{"insert":"\\nAfter\\n"}]',
    );
    final canvas = find.byType(InkCanvas);
    final at = tester.getTopLeft(canvas) + const Offset(40, 30);
    await drag(tester, at, const Offset(200, 0), kind: PointerDeviceKind.touch);
    expect(sketches(tester).single.strokes, isEmpty);
    expect(toolbar, findsNothing);

    await tester.tap(canvas);
    await tester.pumpAndSettle();
    expect(toolbar, findsOneWidget);
    await drag(tester, at, const Offset(200, 0), kind: PointerDeviceKind.touch);
    expect(sketches(tester).single.strokes, hasLength(1));

    // Done puts the tools away; the drawing stays.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(toolbar, findsNothing);
    expect(sketches(tester), hasLength(1));
    await dispose(tester);
  });

  testWidgets('writing with a pen on the text opens a drawing after that '
      'line', (tester) async {
    await openNote(tester, '[{"insert":"First line\\nSecond line\\n"}]');
    final first = find.textContaining('First line', findRichText: true);
    await drag(
      tester,
      tester.getCenter(first) + const Offset(-40, 0),
      const Offset(120, 30),
    );
    expect(text(tester), 'First line\n#\nSecond line\n');
    // On screen too, between the two lines.
    expect(shown(tester).single.strokes, hasLength(1));
    final drawing = tester.getRect(find.byType(InkCanvas));
    expect(drawing.top, greaterThan(tester.getRect(first).bottom - 1));
    final second = tester.getRect(
      find.textContaining('Second', findRichText: true),
    );
    expect(drawing.bottom, lessThan(second.top + 1));
    final sketch = sketches(tester).single;
    expect(sketch.strokes, hasLength(1));
    expect(sketch.strokes.single.points.length, greaterThan(4));
    // No text was selected by the stroke.
    expect(controller(tester).selection.isCollapsed, isTrue);
    expect(toolbar, findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a pen tap on the text places the cursor, drawing nothing', (
    tester,
  ) async {
    await openNote(tester, '[{"insert":"First line\\nSecond line\\n"}]');
    final pen = await tester.startGesture(
      tester.getCenter(find.textContaining('Second', findRichText: true)),
      kind: PointerDeviceKind.stylus,
    );
    await pen.up();
    await tester.pumpAndSettle();
    expect(sketches(tester), isEmpty);
    expect(text(tester), 'First line\nSecond line\n');
    await dispose(tester);
  });

  testWidgets('a pen in the space under the note adds a drawing at the end', (
    tester,
  ) async {
    await openNote(tester, '[{"insert":"Only line\\n"}]');
    final blank = find.byKey(const ValueKey('note-blank-below'));
    await drag(
      tester,
      tester.getTopLeft(blank) + const Offset(60, 40),
      const Offset(150, 20),
    );
    expect(text(tester), 'Only line\n#\n');
    expect(shown(tester), hasLength(1));
    expect(sketches(tester).single.strokes, hasLength(1));
    await dispose(tester);
  });

  testWidgets('writing just below a drawing extends it', (tester) async {
    await openNote(
      tester,
      '[{"insert":"Before\\n"},'
      '${_sketchOp(const Sketch(aspect: 0.3, strokes: [_stroke]))},'
      '{"insert":"\\nAfter\\n"}]',
    );
    final paper = tester.getRect(find.byType(InkCanvas));
    await drag(
      tester,
      Offset(paper.left + 50, paper.bottom + 20),
      const Offset(150, 10),
    );
    final sketch = sketches(tester).single;
    expect(sketch.strokes, hasLength(2));
    expect(shown(tester).single.strokes, hasLength(2));
    expect(sketch.aspect, greaterThan(0.3));
    expect(text(tester), 'Before\n#\nAfter\n');
    await dispose(tester);
  });

  testWidgets('erase, undo, and resize with the handle', (tester) async {
    await openNote(
      tester,
      '[{"insert":"Before\\n"},'
      '${_sketchOp(const Sketch(aspect: 0.4, strokes: [_stroke]))},'
      '{"insert":"\\nAfter\\n"}]',
    );
    final canvas = find.byType(InkCanvas);
    await tester.tap(canvas);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Eraser'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(canvas);
    // Across the stroke, from (0.1, 0.1) to (0.5, 0.2) of the width.
    await drag(
      tester,
      Offset(rect.left + rect.width * 0.3, rect.top + 2),
      Offset(0, rect.width * 0.3),
      kind: PointerDeviceKind.touch,
    );
    expect(sketches(tester).single.strokes, isEmpty);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(sketches(tester).single.strokes, hasLength(1));

    final before = sketches(tester).single.aspect;
    await tester.drag(
      find.byKey(const ValueKey('sketch-resize')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(sketches(tester).single.aspect, greaterThan(before));
    await dispose(tester);
  });

  testWidgets('Draw adds a drawing at the cursor; left empty, it goes', (
    tester,
  ) async {
    await openNote(tester, '[{"insert":"Text\\n"}]');
    await tester.tap(find.byTooltip('Draw'));
    await tester.pumpAndSettle();
    expect(sketches(tester), hasLength(1));
    expect(find.text('Draw here'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(sketches(tester), isEmpty);
    await dispose(tester);
  });

  testWidgets('Expand opens the drawing full screen and keeps the result', (
    tester,
  ) async {
    await openNote(
      tester,
      '[{"insert":"Before\\n"},${_sketchOp(const Sketch(aspect: 0.4))},'
      '{"insert":"\\nAfter\\n"}]',
    );
    await tester.tap(find.byType(InkCanvas));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More drawing options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();
    expect(find.byType(SketchEditorScreen), findsOneWidget);
    final canvas = find.byType(InkCanvas);
    await drag(
      tester,
      tester.getTopLeft(canvas) + const Offset(40, 40),
      const Offset(150, 30),
    );
    await tester.tap(find.text('Done').first);
    await tester.pumpAndSettle();
    expect(find.byType(SketchEditorScreen), findsNothing);
    expect(sketches(tester).single.strokes, hasLength(1));
    await dispose(tester);
  });
}
