import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ink_model.dart';
import 'ink_painter.dart';
import 'ink_session.dart';

/// How far below a drawing a pen can start and still add to it (logical
/// pixels), like writing on past the end of a drawing in Apple Notes.
const extendDrawingReach = 56.0;

/// Room under the note's text for writing with a pen (and tapping to type
/// at the end).
const blankBelowNote = 160.0;

/// A pen recognizer that accepts once the pen has moved a few pixels —
/// sooner than text selection or scrolling would — and lets a plain tap go,
/// so tapping with the pen still places the cursor.
class _PenStrokeRecognizer extends OneSequenceGestureRecognizer {
  _PenStrokeRecognizer()
    : super(
        supportedDevices: {PointerDeviceKind.stylus},
        allowedButtonsFilter: (_) => true,
      );

  void Function(PointerEvent down)? onStart;
  void Function(PointerEvent event)? onUpdate;
  VoidCallback? onEnd;
  VoidCallback? onCancel;

  static const _slop = 3.0;

  PointerDownEvent? _down;
  final _pending = <PointerEvent>[];
  bool _accepted = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_down != null) return; // one stroke at a time
    _down = event;
    _pending.clear();
    _accepted = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (down == null || event.pointer != down.pointer) return;
    if (event is PointerMoveEvent) {
      if (_accepted) {
        onUpdate?.call(event);
      } else {
        _pending.add(event);
        if ((event.position - down.position).distance > _slop) {
          resolve(GestureDisposition.accepted);
        }
      }
    } else if (event is PointerUpEvent) {
      if (_accepted) {
        onEnd?.call();
      } else {
        resolve(GestureDisposition.rejected);
      }
      _reset(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_accepted) onCancel?.call();
      _reset(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {
    final down = _down;
    if (down == null || pointer != down.pointer || _accepted) return;
    _accepted = true;
    onStart?.call(down);
    for (final e in _pending) {
      onUpdate?.call(e);
    }
    _pending.clear();
  }

  @override
  void rejectGesture(int pointer) {
    if (_down?.pointer == pointer) _reset(pointer);
  }

  void _reset(int pointer) {
    stopTrackingPointer(pointer);
    _down = null;
    _pending.clear();
    _accepted = false;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'pen stroke';
}

/// Wraps a note's body editor so a pen can write anywhere in it. A stroke
/// that starts on a drawing is the drawing's own; one that starts just
/// below a drawing extends it; anywhere else — on the text or in the blank
/// space under it — opens a new drawing after that line, holding the
/// stroke, and the text below moves down to make room. Fingers and mice
/// are untouched (they type, select and scroll).
class InkCatcher extends StatefulWidget {
  const InkCatcher({
    super.key,
    required this.session,
    required this.editorKey,
    required this.child,
    this.onTapBelow,
  });

  final InkSession session;
  final GlobalKey<EditorState> editorKey;
  final Widget child;

  /// A finger or mouse tap in the blank space under the text.
  final VoidCallback? onTapBelow;

  @override
  State<InkCatcher> createState() => _InkCatcherState();
}

class _InkCatcherState extends State<InkCatcher> {
  final _stroke = ValueNotifier<List<InkPoint>>(const []);
  final _editorBox = GlobalKey();

  @override
  void dispose() {
    _stroke.dispose();
    super.dispose();
  }

  RenderBox get _box => context.findRenderObject()! as RenderBox;

  double _pressure(PointerEvent e) =>
      normalizePressure(e.pressure, e.pressureMin, e.pressureMax);

  void _start(PointerEvent down) {
    widget.session.onInkStart?.call();
    final at = _box.globalToLocal(down.position);
    _stroke.value = [InkPoint(at.dx, at.dy, _pressure(down))];
  }

  void _update(PointerEvent e) {
    final points = _stroke.value;
    if (points.isEmpty) return;
    final at = _box.globalToLocal(e.position);
    if ((points.last.offset - at).distance < 0.6) return;
    _stroke.value = [...points, InkPoint(at.dx, at.dy, _pressure(e))];
  }

  void _cancel() => _stroke.value = const [];

  void _end() {
    final points = _stroke.value;
    _stroke.value = const [];
    if (points.isEmpty) return;
    final width = _box.size.width;
    if (width <= 0) return;
    final session = widget.session;
    final start = points.first.offset;

    // Just below (or on) a drawing: write on in it.
    for (final drawing in session.drawings) {
      final global = drawing.globalRect;
      if (global == null) continue;
      final rect = Rect.fromPoints(
        _box.globalToLocal(global.topLeft),
        _box.globalToLocal(global.bottomRight),
      );
      if (start.dx < rect.left ||
          start.dx > rect.right ||
          start.dy < rect.top ||
          start.dy > rect.bottom + extendDrawingReach) {
        continue;
      }
      final stroke = _strokeIn(points, rect.topLeft, rect.width);
      final sketch = drawing.sketch;
      session.write(
        drawing.offset,
        sketch.copyWith(
          strokes: [...sketch.strokes, stroke],
          aspect: math.max(
            sketch.aspect,
            math.min(Sketch.maxAspect, stroke.bottom + 0.06),
          ),
        ),
      );
      session.activate(drawing.offset);
      return;
    }

    // Anywhere else: a new drawing after the line the pen started on.
    final place = _placeFor(start);
    if (place == null) return;
    var stroke = _strokeIn(points, Offset(0, place.top), width);
    final top = stroke.points.map((p) => p.y).reduce(math.min);
    if (top < 0.02) stroke = _shifted(stroke, 0.02 - top);
    session.insertDrawing(
      place.index,
      Sketch(
        strokes: [stroke],
        aspect: (stroke.bottom + 0.06).clamp(0.15, Sketch.maxAspect),
      ),
    );
  }

  /// Where a new drawing goes for a pen that started at [start] (local):
  /// the document index after that line, and the drawing's top edge
  /// (local), so the stroke stays where it was drawn when it can.
  ({int index, double top})? _placeFor(Offset start) {
    final render = widget.editorKey.currentState?.renderEditor;
    final editorBox = _editorBox.currentContext?.findRenderObject();
    if (render == null || editorBox is! RenderBox) return null;
    final doc = widget.session.controller.document;
    final editorBottom = _box
        .globalToLocal(
          editorBox.localToGlobal(Offset(0, editorBox.size.height)),
        )
        .dy;
    // The drawing's paper sits under its 8 pt padding.
    const pad = 8.0;
    if (start.dy >= editorBottom) {
      return (index: doc.length - 1, top: editorBottom + pad);
    }
    final position = render.getPositionForOffset(_box.localToGlobal(start));
    var child = doc.queryChild(position.offset);
    var node = child.node;
    if (node is Block) {
      final inner = node.queryChild(child.offset, true);
      node = inner.node ?? node;
    }
    if (node == null) return (index: doc.length - 1, top: editorBottom + pad);
    final lineEnd = node.documentOffset + node.length; // start of next line
    final caret = render.getLocalRectForCaret(
      TextPosition(offset: math.max(0, lineEnd - 1)),
    );
    final bottom = _box
        .globalToLocal(render.localToGlobal(caret.bottomLeft))
        .dy;
    return (index: lineEnd, top: bottom + pad);
  }

  /// [points] (local pixels) as a stroke in canvas-width units of a canvas
  /// whose top-left is [origin] and which is [width] wide.
  InkStroke _strokeIn(List<InkPoint> points, Offset origin, double width) {
    final session = widget.session;
    return InkStroke(
      tool: session.inkTool,
      color: session.color,
      width: session.width,
      points: [
        for (final p in points)
          InkPoint((p.x - origin.dx) / width, (p.y - origin.dy) / width, p.p),
      ],
    );
  }

  InkStroke _shifted(InkStroke s, double dy) => InkStroke(
    tool: s.tool,
    color: s.color,
    width: s.width,
    points: [for (final p in s.points) InkPoint(p.x, p.y + dy, p.p)],
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return RawGestureDetector(
      gestures: {
        _PenStrokeRecognizer:
            GestureRecognizerFactoryWithHandlers<_PenStrokeRecognizer>(
              _PenStrokeRecognizer.new,
              (r) => r
                ..onStart = _start
                ..onUpdate = _update
                ..onEnd = _end
                ..onCancel = _cancel,
            ),
      },
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(key: _editorBox, child: widget.child),
              GestureDetector(
                key: const ValueKey('note-blank-below'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTapBelow,
                child: const SizedBox(height: blankBelowNote),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: _stroke,
                builder: (context, points, _) => points.isEmpty
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _LiveStrokePainter(
                          InkStroke(
                            tool: session.inkTool,
                            color: session.color,
                            // In pixels here: the canvas is 1 unit = 1 px.
                            width: session.width * _box.size.width,
                            points: points,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStrokePainter extends CustomPainter {
  _LiveStrokePainter(this.stroke);

  final InkStroke stroke;

  @override
  void paint(Canvas canvas, Size size) =>
      InkPainter.paintStroke(canvas, stroke, 1);

  @override
  bool shouldRepaint(_LiveStrokePainter old) => old.stroke != stroke;
}
