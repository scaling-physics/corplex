import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/haptics.dart';
import 'free_ink.dart';
import 'ink_canvas.dart' show shapeHoldDelay;
import 'ink_model.dart';
import 'ink_painter.dart';
import 'ink_session.dart';
import 'shape_recognizer.dart';

/// Room under the note's text for writing with a pen (and tapping to type
/// at the end).
const blankBelowNote = 160.0;

/// A pen recognizer that accepts once the pen has moved a few pixels —
/// sooner than text selection or scrolling would — and lets a plain tap go,
/// so tapping with the pen still places the cursor.
class _PenStrokeRecognizer extends OneSequenceGestureRecognizer {
  _PenStrokeRecognizer()
    : super(
        supportedDevices: {
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
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
/// that starts on a drawing is the drawing's own; anywhere else — on the
/// text, in the margins, between paragraphs or in the blank space under the
/// note — is free ink (`free_ink.dart`): it stays exactly where it was drawn,
/// over whatever is there, pinned to the line it started on, and nothing
/// moves. The pen's eraser end, its barrel button or the eraser tool rub
/// free ink out, whole strokes at a time. Fingers and mice are untouched
/// (they type, select and scroll).
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

/// One line's free ink as laid out: its marker, its line's top (pixels in
/// the catcher) and its strokes.
typedef _Placed = ({int offset, double top, String data, FreeInk ink});

class _InkCatcherState extends State<InkCatcher> {
  final _stroke = ValueNotifier<List<InkPoint>>(const []);
  final _editorBox = GlobalKey();

  // Hold to snap (pixels here).
  Timer? _holdTimer;
  Offset? _holdAnchor;
  bool _snapped = false;

  // Free ink as laid out, and the room it needs under the note.
  List<_Placed> _placed = const [];
  double _inkBelow = 0;
  bool _measureQueued = false;

  // An eraser swipe: the strokes it has touched, as (marker, stroke index).
  bool _erasing = false;
  final _rubbed = <(int, int)>{};

  /// How close (pixels) the eraser must pass to take a stroke.
  static const _eraserRadius = 10.0;

  @override
  void initState() {
    super.initState();
    widget.session.controller.addListener(_queueMeasure);
  }

  @override
  void didUpdateWidget(InkCatcher old) {
    super.didUpdateWidget(old);
    if (old.session.controller != widget.session.controller) {
      old.session.controller.removeListener(_queueMeasure);
      widget.session.controller.addListener(_queueMeasure);
    }
  }

  @override
  void dispose() {
    widget.session.controller.removeListener(_queueMeasure);
    _holdTimer?.cancel();
    _stroke.dispose();
    super.dispose();
  }

  RenderBox get _box => context.findRenderObject()! as RenderBox;

  double _pressure(PointerEvent e) =>
      normalizePressure(e.pressure, e.pressureMin, e.pressureMax);

  /// Free ink is placed after layout: lines move whenever the text, the
  /// window width or anything above them changes.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final render = widget.editorKey.currentState?.renderEditor;
    final editorBox = _editorBox.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (render == null ||
        editorBox is! RenderBox ||
        self is! RenderBox ||
        !render.attached ||
        !self.hasSize) {
      return;
    }
    final width = self.size.width;
    final placed = <_Placed>[];
    var lowest = 0.0;
    for (final p in freeInkIn(widget.session.controller.document)) {
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: p.lineStart),
      );
      final top = self.globalToLocal(render.localToGlobal(caret.topLeft)).dy;
      placed.add((
        offset: p.offset,
        top: top,
        data: p.ink.encode(),
        ink: p.ink,
      ));
      lowest = math.max(lowest, top + p.ink.bottom * width);
    }
    final editorBottom = self
        .globalToLocal(
          editorBox.localToGlobal(Offset(0, editorBox.size.height)),
        )
        .dy;
    // Ink written low in the blank space makes room for itself, so the page
    // scrolls far enough to show (and keep writing under) it.
    final below = math.max(0.0, lowest + 24 - editorBottom - blankBelowNote);
    if (below == _inkBelow && _samePlaces(placed)) return;
    setState(() {
      _placed = placed;
      _inkBelow = below;
    });
  }

  bool _samePlaces(List<_Placed> placed) {
    if (placed.length != _placed.length) return false;
    for (var i = 0; i < placed.length; i++) {
      final a = placed[i], b = _placed[i];
      if (a.offset != b.offset || a.top != b.top || a.data != b.data) {
        return false;
      }
    }
    return true;
  }

  bool _isEraser(PointerEvent e) =>
      widget.session.erasing ||
      e.kind == PointerDeviceKind.invertedStylus ||
      e.buttons & kSecondaryStylusButton != 0;

  void _start(PointerEvent down) {
    widget.session.onInkStart?.call();
    // With the selection tool a pen on the text selects nothing and draws
    // nothing: lassoing happens on a drawing.
    if (widget.session.lassoing) return;
    final at = _box.globalToLocal(down.position);
    if (_isEraser(down)) {
      _erasing = true;
      _rubbed.clear();
      _rubAt(at);
      return;
    }
    _snapped = false;
    _holdAnchor = at;
    _stroke.value = [InkPoint(at.dx, at.dy, _pressure(down))];
    _restartHold();
  }

  void _update(PointerEvent e) {
    if (_erasing) {
      _rubAt(_box.globalToLocal(e.position));
      return;
    }
    final points = _stroke.value;
    if (points.isEmpty || _snapped) return;
    final at = _box.globalToLocal(e.position);
    if ((at - _holdAnchor!).distance > 3) {
      _holdAnchor = at;
      _restartHold();
    }
    if ((points.last.offset - at).distance < 0.6) return;
    _stroke.value = [...points, InkPoint(at.dx, at.dy, _pressure(e))];
  }

  /// Marks the free-ink strokes under the eraser at [at] (local pixels);
  /// they disappear at once and are removed when the swipe ends.
  void _rubAt(Offset at) {
    final width = _box.size.width;
    if (width <= 0) return;
    var added = false;
    for (final p in _placed) {
      final local = Offset(at.dx / width, (at.dy - p.top) / width);
      for (var i = 0; i < p.ink.strokes.length; i++) {
        if (_rubbed.contains((p.offset, i))) continue;
        if (p.ink.strokes[i].hits(local, _eraserRadius / width)) {
          _rubbed.add((p.offset, i));
          added = true;
        }
      }
    }
    if (added) setState(() {});
  }

  void _restartHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(shapeHoldDelay, _snapToShape);
  }

  /// Held still at the end: a line, circle, box, triangle or arrow becomes
  /// the clean shape.
  void _snapToShape() {
    final points = _stroke.value;
    if (points.isEmpty || _snapped) return;
    final width = _box.size.width;
    final shape = recognizeShape(points, minLength: 0.08 * width);
    if (shape == null) return;
    _snapped = true;
    _stroke.value = shape;
    AppHaptics.threshold();
  }

  void _cancel() {
    _holdTimer?.cancel();
    _stroke.value = const [];
    if (_erasing) {
      setState(() {
        _erasing = false;
        _rubbed.clear();
      });
    }
  }

  void _end() {
    _holdTimer?.cancel();
    if (_erasing) {
      _endErasing();
      return;
    }
    _snapped = false;
    final points = _stroke.value;
    _stroke.value = const [];
    if (points.isEmpty) return;
    final width = _box.size.width;
    if (width <= 0) return;
    final session = widget.session;
    final start = points.first.offset;

    // On a drawing: write on in it.
    for (final drawing in session.drawings) {
      final global = drawing.globalRect;
      if (global == null) continue;
      final rect = Rect.fromPoints(
        _box.globalToLocal(global.topLeft),
        _box.globalToLocal(global.bottomRight),
      );
      if (!rect.contains(start)) continue;
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

    // Anywhere else: free ink, pinned to the line the pen started on.
    final anchor = _anchorFor(start);
    if (anchor == null) return;
    session.addFreeInk(
      anchor.offset,
      _strokeIn(points, Offset(0, anchor.top), width),
    );
  }

  void _endErasing() {
    final rubbed = {..._rubbed};
    setState(() {
      _erasing = false;
      _rubbed.clear();
    });
    if (rubbed.isEmpty) return;
    final changed = <int, FreeInk>{};
    for (final p in _placed) {
      if (!rubbed.any((r) => r.$1 == p.offset)) continue;
      changed[p.offset] = FreeInk([
        for (var i = 0; i < p.ink.strokes.length; i++)
          if (!rubbed.contains((p.offset, i))) p.ink.strokes[i],
      ]);
    }
    widget.session.replaceFreeInk(changed);
  }

  /// The line free ink started at [start] (local) is pinned to: a document
  /// offset on it, and its top (local) — the origin of the ink's y.
  ({int offset, double top})? _anchorFor(Offset start) {
    final render = widget.editorKey.currentState?.renderEditor;
    final editorBox = _editorBox.currentContext?.findRenderObject();
    if (render == null || editorBox is! RenderBox) return null;
    final doc = widget.session.controller.document;
    final editorBottom = _box
        .globalToLocal(
          editorBox.localToGlobal(Offset(0, editorBox.size.height)),
        )
        .dy;
    final at = start.dy >= editorBottom
        ? doc.length - 1
        : render.getPositionForOffset(_box.localToGlobal(start)).offset;
    final line = freeInkLine(doc, at);
    if (line == null) return null;
    final caret = render.getLocalRectForCaret(
      TextPosition(offset: line.documentOffset),
    );
    final top = _box.globalToLocal(render.localToGlobal(caret.topLeft)).dy;
    return (offset: line.documentOffset, top: top);
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    _queueMeasure();
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
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  _queueMeasure();
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: KeyedSubtree(key: _editorBox, child: widget.child),
                ),
              ),
              GestureDetector(
                key: const ValueKey('note-blank-below'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTapBelow,
                child: SizedBox(height: blankBelowNote + _inkBelow),
              ),
            ],
          ),
          if (_placed.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('free-ink'),
                  painter: _FreeInkPainter(_placed, {..._rubbed}),
                ),
              ),
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

/// All of a note's free ink, each line's strokes from that line's top, at
/// the catcher's width; strokes under an eraser swipe ([hidden]) are left
/// out. Highlighter first, so it never mutes the pen on top.
class _FreeInkPainter extends CustomPainter {
  _FreeInkPainter(this.placed, this.hidden);

  final List<_Placed> placed;
  final Set<(int, int)> hidden;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width;
    for (final tool in [InkTool.highlighter, InkTool.pen]) {
      for (final p in placed) {
        canvas.save();
        canvas.translate(0, p.top);
        for (var i = 0; i < p.ink.strokes.length; i++) {
          final s = p.ink.strokes[i];
          if (s.tool != tool || hidden.contains((p.offset, i))) continue;
          InkPainter.paintStroke(canvas, s, scale);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_FreeInkPainter old) =>
      old.placed != placed || !setEquals(old.hidden, hidden);
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
