import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink_model.dart';
import 'ink_painter.dart';

/// What a pointer on the canvas should do.
enum InkAction { draw, erase, ignore }

/// Decides what each pointer does — the palm-rejection policy.
///
/// Once a stylus (Apple Pencil, S Pen, USI pen…) has touched the canvas,
/// fingers stop drawing and scroll instead, so a palm resting on an iPad
/// never leaves marks. Before any stylus is seen (phones, or tablets
/// without a pen), fingers draw — unless the user has switched finger
/// drawing off. A stylus flipped to its eraser end always erases.
class InkInputPolicy {
  bool stylusSeen = false;

  /// null = automatic (draw with fingers until a stylus appears).
  bool? fingerDrawsOverride;

  bool get fingersDraw => fingerDrawsOverride ?? !stylusSeen;

  /// On a desktop a mouse or trackpad click is the main way to draw, whether
  /// or not a pen tablet has also been used (there are no palms to reject).
  bool mouseAlwaysDraws = false;

  /// [stylusButton] is the pen's barrel button (S Pen, Wacom-style styluses):
  /// held while touching, it erases, like flipping a pencil over.
  InkAction actionFor(
    PointerDeviceKind kind, {
    required bool eraserTool,
    bool stylusButton = false,
  }) {
    switch (kind) {
      case PointerDeviceKind.invertedStylus:
        stylusSeen = true;
        return InkAction.erase;
      case PointerDeviceKind.stylus:
        stylusSeen = true;
        return eraserTool || stylusButton ? InkAction.erase : InkAction.draw;
      case PointerDeviceKind.mouse:
        if (!fingersDraw && !mouseAlwaysDraws) return InkAction.ignore;
        return eraserTool ? InkAction.erase : InkAction.draw;
      case PointerDeviceKind.touch:
        if (!fingersDraw) return InkAction.ignore;
        return eraserTool ? InkAction.erase : InkAction.draw;
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
        return InkAction.ignore;
    }
  }
}

/// The app's one palm-rejection policy: once a pen has been used anywhere,
/// fingers stop drawing for the rest of the session.
final inkPolicy = InkInputPolicy();

/// Claims a pointer the canvas is drawing or erasing with as soon as it
/// touches down, so the note's text selection, the page's scrolling and
/// other gestures under the canvas never act on a pen stroke.
class InkClaimRecognizer extends OneSequenceGestureRecognizer {
  InkClaimRecognizer(this.claims) : super(allowedButtonsFilter: (_) => true);

  final bool Function(int pointer) claims;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!claims(event.pointer)) return;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ink claim';
}

/// The drawing surface. Reports every finished stroke or erase through
/// [onChanged]; it doesn't own the sketch, so the editor can keep undo
/// history.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.sketch,
    required this.onChanged,
    required this.policy,
    required this.tool,
    required this.color,
    required this.width,
    required this.erasing,
    this.onGestureStart,
    this.onPolicyChanged,
    this.othersDraw = true,
  });

  /// Whether fingers and a mouse may draw here (still subject to [policy]).
  /// A pen always may. Inline drawings in a note pass false until the
  /// drawing is chosen, so a finger scrolls past it.
  final bool othersDraw;

  final Sketch sketch;
  final ValueChanged<Sketch> onChanged;
  final InkInputPolicy policy;
  final InkTool tool;
  final Color color;

  /// Line width in canvas-width units.
  final double width;
  final bool erasing;

  /// Called as a stroke or erase gesture begins — the editor snapshots the
  /// sketch here, so one gesture (however many strokes an eraser swipe
  /// removes) is one undo step.
  final VoidCallback? onGestureStart;

  /// Called when the policy flips (a stylus was just detected), so the
  /// screen can update scrolling and its finger-drawing toggle.
  final VoidCallback? onPolicyChanged;

  @override
  State<InkCanvas> createState() => _InkCanvasState();
}

class _InkCanvasState extends State<InkCanvas> {
  final _active = ValueNotifier<InkStroke?>(null);

  /// Where a hovering pen is (canvas pixels) and whether it would erase;
  /// null when nothing hovers. Apple Pencil (M2 iPads) and Android styluses
  /// report hover before they touch.
  final _hover = ValueNotifier<({Offset at, bool erase})?>(null);
  int? _pointer;
  InkAction _action = InkAction.ignore;
  double _canvasWidth = 1;

  /// The sketch as this erase gesture has left it so far. Pointer moves
  /// can arrive faster than the parent rebuilds, so erasing against
  /// `widget.sketch` would resurrect strokes removed a moment earlier.
  Sketch? _erasing;

  static const _eraserRadius = 0.02;
  static const _minPointGap = 0.0015;

  @override
  void dispose() {
    _active.dispose();
    _hover.dispose();
    super.dispose();
  }

  Offset _normalize(Offset local) => local / _canvasWidth;

  double _pressure(PointerEvent e) => e.kind == PointerDeviceKind.stylus
      ? normalizePressure(e.pressure, e.pressureMin, e.pressureMax)
      : 0.5;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return; // one stroke at a time
    final hadStylus = widget.policy.stylusSeen;
    final action = widget.policy.actionFor(
      e.kind,
      eraserTool: widget.erasing,
      stylusButton: e.buttons & kSecondaryStylusButton != 0,
    );
    _hover.value = null;
    if (!hadStylus && widget.policy.stylusSeen) widget.onPolicyChanged?.call();
    if (action == InkAction.ignore) return;
    final pen =
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (!pen && !widget.othersDraw) return;

    _pointer = e.pointer;
    _action = action;
    widget.onGestureStart?.call();
    final at = _normalize(e.localPosition);
    if (action == InkAction.erase) {
      _erasing = widget.sketch;
      _eraseAt(at);
    } else {
      _active.value = InkStroke(
        tool: widget.tool,
        color: widget.color,
        width: widget.width,
        points: [InkPoint(at.dx, at.dy, _pressure(e))],
      );
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final at = _normalize(e.localPosition);
    if (_action == InkAction.erase) {
      _eraseAt(at);
      return;
    }
    final stroke = _active.value;
    if (stroke == null) return;
    // Skip jitter: points closer than a fraction of a pixel add weight to
    // the saved note without changing the line.
    if ((stroke.points.last.offset - at).distance < _minPointGap) return;
    _active.value = InkStroke(
      tool: stroke.tool,
      color: stroke.color,
      width: stroke.width,
      points: [...stroke.points, InkPoint(at.dx, at.dy, _pressure(e))],
    );
  }

  void _hovered(PointerHoverEvent e) {
    if (_pointer != null ||
        (e.kind != PointerDeviceKind.stylus &&
            e.kind != PointerDeviceKind.invertedStylus)) {
      return;
    }
    _hover.value = (
      at: e.localPosition,
      erase:
          widget.erasing ||
          e.kind == PointerDeviceKind.invertedStylus ||
          e.buttons & kSecondaryStylusButton != 0,
    );
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (_action == InkAction.erase) {
      // One write per swipe, however many strokes it crossed.
      final erased = _erasing;
      _erasing = null;
      if (erased != null && !identical(erased, widget.sketch)) {
        widget.onChanged(erased);
      } else {
        setState(() {});
      }
      return;
    }
    if (_action == InkAction.draw) {
      final stroke = _active.value;
      _active.value = null;
      if (stroke != null) {
        final bottom = stroke.bottom;
        // Grow the page as you write near its end.
        final aspect = bottom > widget.sketch.aspect - 0.12
            ? math.min(Sketch.maxAspect, bottom + 0.35)
            : widget.sketch.aspect;
        widget.onChanged(
          widget.sketch.copyWith(
            strokes: [...widget.sketch.strokes, stroke],
            aspect: math.max(aspect, widget.sketch.aspect),
          ),
        );
      }
    }
    _erasing = null;
  }

  void _eraseAt(Offset at) {
    final current = _erasing!;
    final remaining = current.strokes
        .where((s) => !s.hits(at, _eraserRadius))
        .toList();
    if (remaining.length != current.strokes.length) {
      setState(() => _erasing = current.copyWith(strokes: remaining));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        return RawGestureDetector(
          gestures: {
            InkClaimRecognizer:
                GestureRecognizerFactoryWithHandlers<InkClaimRecognizer>(
                  () => InkClaimRecognizer((p) => p == _pointer),
                  (_) {},
                ),
          },
          child: MouseRegion(
            onHover: _hovered,
            onExit: (_) => _hover.value = null,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxWidth * widget.sketch.aspect,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: InkPainter(
                      strokes: (_erasing ?? widget.sketch).strokes,
                    ),
                    foregroundPainter: _ActiveStrokePainter(_active),
                    child: ValueListenableBuilder(
                      valueListenable: _hover,
                      builder: (context, hover, _) => hover == null
                          ? const SizedBox.expand()
                          : CustomPaint(
                              key: const ValueKey('ink-hover'),
                              painter: _HoverPainter(
                                at: hover.at,
                                radius: hover.erase
                                    ? _eraserRadius * _canvasWidth
                                    : widget.width * _canvasWidth / 2,
                                erase: hover.erase,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints only the stroke being drawn, so moving the pen repaints one
/// line instead of the whole sketch.
class _ActiveStrokePainter extends CustomPainter {
  _ActiveStrokePainter(this.active) : super(repaint: active);

  final ValueNotifier<InkStroke?> active;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = active.value;
    if (stroke != null) InkPainter.paintStroke(canvas, stroke, size.width);
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter old) => old.active != active;
}

/// The ring that follows a hovering pen: the size of the mark it would
/// make, so you can aim before touching down.
class _HoverPainter extends CustomPainter {
  _HoverPainter({required this.at, required this.radius, required this.erase});

  final Offset at;
  final double radius;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      at,
      radius.clamp(3, 60),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = erase ? const Color(0xFFB5654A) : const Color(0x99000000),
    );
  }

  @override
  bool shouldRepaint(_HoverPainter old) =>
      old.at != at || old.radius != radius || old.erase != erase;
}
