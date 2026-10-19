import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/haptics.dart';
import 'ink_model.dart';
import 'ink_painter.dart';
import 'ink_tools.dart';
import 'shape_recognizer.dart';
import 'sketch_render.dart';

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

/// Strokes copied with the selection menu (canvas-width units), for Paste.
List<InkStroke> inkClipboard = const [];

/// How long the pen holds still at the end of a stroke before the stroke
/// snaps to the clean shape it resembles.
const shapeHoldDelay = Duration(milliseconds: 500);

/// How far (canvas-width units) the pen may drift and still count as still.
const _holdTolerance = 0.006;

enum _Gesture { none, lasso, move }

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
    this.lasso = false,
    this.keepSelection = true,
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

  /// The lasso is the tool: drawing a loop selects strokes instead of
  /// inking, and the selection can be moved, copied, recoloured, duplicated
  /// or deleted.
  final bool lasso;

  /// False when another drawing is the chosen one: this canvas lets go of
  /// its selection.
  final bool keepSelection;

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

  // Hold to snap.
  Timer? _holdTimer;
  Offset? _holdAnchor;
  bool _snapped = false;

  // Lasso.
  _Gesture _gesture = _Gesture.none;
  final _lassoPath = ValueNotifier<List<Offset>>(const []);
  Set<int> _selected = {};
  int _selectionFor = 0;
  Offset _moveStart = Offset.zero;
  Offset _moveDelta = Offset.zero;

  /// The sketch just after a move or menu action, shown until the parent
  /// hands the written sketch back.
  Sketch? _written;

  static const _eraserRadius = 0.02;
  static const _minPointGap = 0.0015;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _active.dispose();
    _hover.dispose();
    _lassoPath.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InkCanvas old) {
    super.didUpdateWidget(old);
    if (!identical(old.sketch, widget.sketch)) _written = null;
    if (_selected.isNotEmpty &&
        (!widget.lasso ||
            !widget.keepSelection ||
            widget.sketch.strokes.length != _selectionFor)) {
      _selected = {};
    }
  }

  Offset _normalize(Offset local) => local / _canvasWidth;

  List<InkStroke> get _baseStrokes =>
      (_written ?? _erasing ?? widget.sketch).strokes;

  /// What is painted: the sketch, with a selection being dragged moved.
  List<InkStroke> get _shownStrokes {
    final base = _baseStrokes;
    if (_gesture != _Gesture.move || _moveDelta == Offset.zero) return base;
    return [
      for (var i = 0; i < base.length; i++)
        _selected.contains(i) ? base[i].translated(_moveDelta) : base[i],
    ];
  }

  Rect? get _selectionBounds {
    final shown = _shownStrokes;
    Rect? box;
    for (final i in _selected) {
      if (i >= shown.length) continue;
      final b = shown[i].bounds;
      box = box == null ? b : box.expandToInclude(b);
    }
    return box;
  }

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
    } else if (widget.lasso) {
      _beginLasso(at);
    } else {
      _snapped = false;
      _holdAnchor = at;
      _active.value = InkStroke(
        tool: widget.tool,
        color: widget.color,
        width: widget.width,
        points: [InkPoint(at.dx, at.dy, _pressure(e))],
      );
      _restartHold();
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final at = _normalize(e.localPosition);
    if (_action == InkAction.erase) {
      _eraseAt(at);
      return;
    }
    if (widget.lasso) {
      _lassoMoved(at);
      return;
    }
    final stroke = _active.value;
    if (stroke == null || _snapped) return;
    if ((at - _holdAnchor!).distance > _holdTolerance) {
      _holdAnchor = at;
      _restartHold();
    }
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

  void _restartHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(shapeHoldDelay, _snapToShape);
  }

  /// The pen has been still long enough: swap the stroke for the clean
  /// shape it resembles, if it resembles one.
  void _snapToShape() {
    final stroke = _active.value;
    if (stroke == null || _pointer == null || _snapped) return;
    final shape = recognizeShape(stroke.points);
    if (shape == null) return;
    _snapped = true;
    _active.value = stroke.copyWith(points: shape);
    AppHaptics.threshold();
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
    _holdTimer?.cancel();
    _snapped = false;
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
    if (_action == InkAction.draw && widget.lasso) {
      _endLasso(cancelled: e is PointerCancelEvent);
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

  // ------------------------------------------------------------- lasso ---

  void _beginLasso(Offset at) {
    _written = null;
    final box = _selectionBounds;
    if (box != null && box.inflate(0.015).contains(at)) {
      setState(() {
        _gesture = _Gesture.move;
        _moveStart = at;
        _moveDelta = Offset.zero;
      });
    } else {
      setState(() {
        _gesture = _Gesture.lasso;
        _selected = {};
        _lassoPath.value = [at];
      });
    }
  }

  void _lassoMoved(Offset at) {
    switch (_gesture) {
      case _Gesture.lasso:
        final path = _lassoPath.value;
        if (path.isEmpty || (path.last - at).distance > 0.004) {
          _lassoPath.value = [...path, at];
        }
      case _Gesture.move:
        final box = _selectionBounds;
        if (box == null) return;
        // The whole selection stays on the page sideways and at the top;
        // downwards the page grows.
        final raw = box.shift(-_moveDelta);
        var d = at - _moveStart;
        d = Offset(
          d.dx.clamp(-raw.left, 1 - raw.right),
          math.max(d.dy, -raw.top),
        );
        setState(() => _moveDelta = d);
      case _Gesture.none:
        break;
    }
  }

  void _endLasso({required bool cancelled}) {
    final gesture = _gesture;
    _gesture = _Gesture.none;
    if (gesture == _Gesture.move) {
      final delta = _moveDelta;
      _moveDelta = Offset.zero;
      if (cancelled || delta.distance < 0.002) {
        setState(() {});
        return;
      }
      final base = widget.sketch;
      var bottom = 0.0;
      final moved = [
        for (var i = 0; i < base.strokes.length; i++)
          if (_selected.contains(i))
            () {
              final s = base.strokes[i].translated(delta);
              bottom = math.max(bottom, s.bounds.bottom);
              return s;
            }()
          else
            base.strokes[i],
      ];
      _commit(
        base.copyWith(
          strokes: moved,
          aspect: bottom > base.aspect - 0.02
              ? math.min(Sketch.maxAspect, bottom + 0.06)
              : base.aspect,
        ),
      );
      return;
    }
    final path = _lassoPath.value;
    _lassoPath.value = const [];
    final picked = <int>{};
    if (!cancelled && path.length > 3) {
      final strokes = widget.sketch.strokes;
      for (var i = 0; i < strokes.length; i++) {
        final pts = strokes[i].points;
        if (pts.isEmpty) continue;
        final inside = pts.where((p) => _inPolygon(p.offset, path)).length;
        if (inside * 2 > pts.length) picked.add(i);
      }
    }
    setState(() {
      _selected = picked;
      _selectionFor = widget.sketch.strokes.length;
    });
  }

  /// Writes [next] (one undo step) and shows it until the parent catches up.
  void _commit(Sketch next, {Set<int>? select}) {
    setState(() {
      _written = next;
      _selected = select ?? _selected;
      _selectionFor = next.strokes.length;
    });
    widget.onChanged(next);
  }

  List<InkStroke> get _selectedStrokes => [
    for (final i in _selected.toList()..sort())
      if (i < widget.sketch.strokes.length) widget.sketch.strokes[i],
  ];

  void _copy() {
    inkClipboard = _selectedStrokes;
    Clipboard.setData(
      ClipboardData(
        text: sketchToSvg(Sketch(strokes: inkClipboard, aspect: 1)),
      ),
    );
    AppHaptics.selection();
    setState(() {});
  }

  void _duplicate() => _addStrokes(_selectedStrokes);

  void _paste() => _addStrokes(inkClipboard);

  void _addStrokes(List<InkStroke> strokes) {
    if (strokes.isEmpty) return;
    widget.onGestureStart?.call();
    final base = widget.sketch;
    const nudge = Offset(0.03, 0.03);
    final added = [for (final s in strokes) s.translated(nudge)];
    final all = [...base.strokes, ...added];
    final bottom = added.fold<double>(
      0,
      (m, s) => math.max(m, s.bounds.bottom),
    );
    _commit(
      base.copyWith(
        strokes: all,
        aspect: bottom > base.aspect - 0.02
            ? math.min(Sketch.maxAspect, bottom + 0.06)
            : base.aspect,
      ),
      select: {for (var i = base.strokes.length; i < all.length; i++) i},
    );
  }

  void _recolor(int ink) {
    widget.onGestureStart?.call();
    final base = widget.sketch;
    _commit(
      base.copyWith(
        strokes: [
          for (var i = 0; i < base.strokes.length; i++)
            if (_selected.contains(i))
              base.strokes[i].copyWith(
                color: base.strokes[i].tool == InkTool.highlighter
                    ? highlighterInks[ink]
                    : penInks[ink],
              )
            else
              base.strokes[i],
        ],
      ),
    );
  }

  void _delete() {
    widget.onGestureStart?.call();
    final base = widget.sketch;
    _commit(
      base.copyWith(
        strokes: [
          for (var i = 0; i < base.strokes.length; i++)
            if (!_selected.contains(i)) base.strokes[i],
        ],
      ),
      select: <int>{},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        final height = constraints.maxWidth * widget.sketch.aspect;
        final box = _gesture == _Gesture.move || _selected.isEmpty
            ? null
            : _selectionBounds;
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
            child: Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: height,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: InkPainter(strokes: _shownStrokes),
                        foregroundPainter: _ActiveStrokePainter(_active),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ValueListenableBuilder(
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
                            if (_selected.isNotEmpty ||
                                _gesture == _Gesture.lasso)
                              IgnorePointer(
                                child: ValueListenableBuilder(
                                  valueListenable: _lassoPath,
                                  builder: (context, path, _) => CustomPaint(
                                    key: const ValueKey('ink-selection'),
                                    painter: _SelectionPainter(
                                      color: c.primary,
                                      strokes: [
                                        for (final i in _selected)
                                          if (i < _shownStrokes.length)
                                            _shownStrokes[i],
                                      ],
                                      box: _selectionBounds,
                                      lasso: path,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (box != null)
                  _positioned(
                    box,
                    constraints.maxWidth,
                    height,
                    _SelectionMenu(
                      onCopy: _copy,
                      onDuplicate: _duplicate,
                      onColor: _recolor,
                      onDelete: _delete,
                    ),
                  ),
                if (widget.lasso &&
                    widget.keepSelection &&
                    _selected.isEmpty &&
                    _gesture == _Gesture.none &&
                    inkClipboard.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: ActionChip(
                      key: const ValueKey('ink-paste'),
                      avatar: const Icon(Icons.content_paste, size: 16),
                      label: Text(context.l10n.inkPaste),
                      visualDensity: VisualDensity.compact,
                      onPressed: _paste,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The selection menu, above the selection when there is room, else
  /// below it, and always inside the page.
  Widget _positioned(Rect box, double width, double height, Widget menu) {
    const menuWidth = 176.0;
    const menuHeight = 44.0;
    final left = (box.center.dx * width - menuWidth / 2)
        .clamp(4.0, math.max(4.0, width - menuWidth - 4))
        .toDouble();
    var top = box.top * width - menuHeight - 6;
    if (top < 4) top = box.bottom * width + 6;
    top = top.clamp(4.0, math.max(4.0, height - menuHeight - 4)).toDouble();
    return Positioned(left: left, top: top, child: menu);
  }
}

bool _inPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Edit actions for the selected strokes.
class _SelectionMenu extends StatelessWidget {
  const _SelectionMenu({
    required this.onCopy,
    required this.onDuplicate,
    required this.onColor,
    required this.onDelete,
  });

  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final ValueChanged<int> onColor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget button(Key key, IconData icon, String tip, VoidCallback onTap) =>
        IconButton(
          key: key,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          tooltip: tip,
          onPressed: onTap,
        );
    return Material(
      key: const ValueKey('ink-selection-menu'),
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            const ValueKey('ink-sel-copy'),
            Icons.copy,
            context.l10n.commonCopy,
            onCopy,
          ),
          button(
            const ValueKey('ink-sel-duplicate'),
            Icons.control_point_duplicate,
            context.l10n.inkDuplicate,
            onDuplicate,
          ),
          PopupMenuButton<int>(
            key: const ValueKey('ink-sel-color'),
            tooltip: context.l10n.inkColour,
            icon: const Icon(Icons.palette_outlined, size: 20),
            padding: EdgeInsets.zero,
            onSelected: onColor,
            itemBuilder: (_) => [
              for (var i = 0; i < penInks.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: penInks[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        [
                          context.l10n.inkGraphite,
                          context.l10n.inkSage,
                          context.l10n.inkClay,
                          context.l10n.inkBlue,
                        ][i],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          button(
            const ValueKey('ink-sel-delete'),
            Icons.delete_outline,
            context.l10n.commonDelete,
            onDelete,
          ),
        ],
      ),
    );
  }
}

/// The soft glow behind selected strokes, their box, and the loop being
/// drawn.
class _SelectionPainter extends CustomPainter {
  _SelectionPainter({
    required this.color,
    required this.strokes,
    required this.box,
    required this.lasso,
  });

  final Color color;
  final List<InkStroke> strokes;
  final Rect? box;
  final List<Offset> lasso;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      glow.strokeWidth = stroke.width * s + 8;
      final path = Path()
        ..moveTo(stroke.points.first.x * s, stroke.points.first.y * s);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.x * s, p.y * s);
      }
      if (stroke.points.length == 1) path.relativeLineTo(0.1, 0);
      canvas.drawPath(path, glow);
    }
    final b = box;
    if (b != null) {
      final r = Rect.fromLTRB(
        b.left * s,
        b.top * s,
        b.right * s,
        b.bottom * s,
      ).inflate(6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    if (lasso.length > 1) {
      final path = Path()..moveTo(lasso.first.dx * s, lasso.first.dy * s);
      for (final p in lasso.skip(1)) {
        path.lineTo(p.dx * s, p.dy * s);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
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
