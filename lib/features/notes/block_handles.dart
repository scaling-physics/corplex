import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'block_ops.dart';
import 'heading_fold.dart';
import 'heading_fold_controller.dart';

/// Where the pointer (mouse hover) or a long press (touch) is on the page,
/// for the block handles. The handles are invisible until one of the two
/// is in the left margin of a line.
class BlockHandleHub extends ChangeNotifier {
  Offset? hover;
  Offset? touch;
  Timer? _timer;
  Offset? _down;

  /// Right edge (global x) of the zone where a touch keeps the handle.
  double zoneRight = 0;
  double zoneLeft = 0;

  void setHover(Offset? p) {
    if (hover == p) return;
    hover = p;
    notifyListeners();
  }

  void clearTouch() {
    if (touch == null) return;
    touch = null;
    notifyListeners();
  }

  void pointerDown(PointerDownEvent e) {
    _timer?.cancel();
    if (e.kind != PointerDeviceKind.touch) return;
    final inZone = e.position.dx >= zoneLeft && e.position.dx <= zoneRight;
    if (!inZone) {
      clearTouch();
      return;
    }
    if (touch != null) return;
    _down = e.position;
    _timer = Timer(const Duration(milliseconds: 500), () {
      touch = _down;
      notifyListeners();
    });
  }

  void pointerMove(PointerMoveEvent e) {
    final d = _down;
    if (d != null && (e.position - d).distance > 10) _timer?.cancel();
  }

  void pointerEnd() {
    _timer?.cancel();
    _down = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Feeds long presses in the margin to a [BlockHandleHub] (touch only).
class BlockHandleTouch extends StatelessWidget {
  const BlockHandleTouch({super.key, required this.hub, required this.child});

  final BlockHandleHub hub;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: hub.pointerDown,
    onPointerMove: hub.pointerMove,
    onPointerUp: (_) => hub.pointerEnd(),
    onPointerCancel: (_) => hub.pointerEnd(),
    child: child,
  );
}

/// Applies [next] (the editor's lines after an edit) as one undoable Quill
/// edit and puts the caret at the start of line [caretLine].
void applyBlockEdit(
  QuillController controller,
  List<FoldLine> current,
  List<FoldLine> next, {
  int? caretLine,
  bool caretAtEnd = false,
}) {
  final change = lineReplacement(current, next);
  if (change.isEmpty) return;
  var caret = 0;
  final stop = (caretLine ?? 0).clamp(0, next.length);
  for (var i = 0; i < stop; i++) {
    caret += next[i].length;
  }
  if (caretAtEnd && stop < next.length) caret += next[stop].length - 1;
  final doc = controller.document;
  // Never merged into the typing before it: one move, one undo.
  doc.history.lastRecorded = 0;
  final selection = TextSelection.collapsed(
    offset: caret.clamp(0, doc.length - 1),
  );
  controller.compose(change, selection, ChangeSource.local);
  // compose keeps the old selection (moved through the change): say where
  // the caret goes.
  controller.updateSelection(selection, ChangeSource.local);
  doc.history.lastRecorded = 0;
}

/// The index of the line holding the caret, or null.
int? lineAtOffset(List<FoldLine> lines, int offset) {
  var at = 0;
  for (var i = 0; i < lines.length; i++) {
    if (offset < at + lines[i].length) return i;
    at += lines[i].length;
  }
  return lines.isEmpty ? null : lines.length - 1;
}

/// ⌃⌘↑ / ⌃⌘↓: moves the block holding the caret one block up ([by] < 0) or
/// down. Returns whether anything moved.
bool moveBlockAtCaret(QuillController controller, HeadingFolds folds, int by) {
  final sel = controller.selection;
  if (!sel.isValid) return false;
  final lines = folds.lines;
  var i = lineAtOffset(lines, sel.start);
  if (i == null) return false;
  i = blockStart(lines, i);
  final (from, to) = blockSpan(lines, i);
  final dest = stepDestination(lines, i, by);
  if (dest == null) return false;
  final next = moveLines(lines, from, to, dest);
  if (next == null) return false;
  final at = dest > to ? dest - (to - from) : dest;
  applyBlockEdit(controller, lines, next, caretLine: at);
  folds.documentChanged();
  return true;
}

/// The drag handles in the left margin of a note's lines: drag to move a
/// line (hold ⌥ to take its section along), tap for Turn into, Duplicate,
/// Delete, Move up/down and Copy link. Nothing shows until the mouse is in
/// a line's left margin, or a finger long-presses there; the handle then
/// fades in, small and quiet, and out again.
class BlockHandles extends StatefulWidget {
  const BlockHandles({
    super.key,
    required this.folds,
    required this.controller,
    required this.editorKey,
    required this.scroll,
    required this.hub,
    this.onCopyLink,
  });

  final HeadingFolds folds;
  final QuillController controller;
  final GlobalKey<EditorState> editorKey;
  final ScrollController scroll;
  final BlockHandleHub hub;

  /// Copies a link to the block at the editor offset [lineStart]; null hides
  /// the menu item.
  final Future<void> Function(int lineStart)? onCopyLink;

  @override
  State<BlockHandles> createState() => _BlockHandlesState();
}

class _Spot {
  const _Spot(this.line, this.x, this.y);
  final int line;
  final double x;

  /// Vertical centre of the line's first row, local to the overlay.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is _Spot &&
      other.line == line &&
      (other.x - x).abs() < 0.5 &&
      (other.y - y).abs() < 0.5;

  @override
  int get hashCode => line.hashCode;
}

class _BlockHandlesState extends State<BlockHandles> {
  static const _width = 22.0;
  static const _height = 28.0;

  _Spot? _spot;
  _Spot? _last;
  bool _busy = false;
  int? _dragFrom;
  int? _dragTo;
  int? _dropAt;
  double? _dropY;
  bool _withSection = false;

  late final Listenable _merged = Listenable.merge([
    widget.hub,
    widget.scroll,
    widget.controller,
  ]);

  @override
  void initState() {
    super.initState();
    _merged.addListener(_changed);
  }

  @override
  void dispose() {
    _merged.removeListener(_changed);
    super.dispose();
  }

  RenderEditor? get _render {
    final r = widget.editorKey.currentState?.renderEditor;
    return r != null && r.attached ? r : null;
  }

  double? _scrollAt;

  void _changed() {
    if (!mounted || _busy) return;
    if (widget.scroll.hasClients) {
      final at = widget.scroll.offset;
      if (_scrollAt != null && (at - _scrollAt!).abs() > 8) {
        widget.hub.touch = null;
      }
      _scrollAt = at;
    }
    // A sideways mouse move changes nothing else on screen, so ask for a
    // frame to measure in.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _measure();
      if (next != _spot) {
        setState(() {
          _spot = next;
          if (next != null) _last = next;
        });
      }
    });
  }

  /// Global y range of line [i] (its first row's top to its last row's
  /// bottom), or null before layout.
  (double, double)? _lineRange(
    RenderEditor render,
    List<FoldLine> lines,
    int i,
  ) {
    var start = 0;
    for (var k = 0; k < i; k++) {
      start += lines[k].length;
    }
    try {
      final top = render.getLocalRectForCaret(TextPosition(offset: start));
      final endOffset = start + lines[i].length - 1;
      final bottom = render.getLocalRectForCaret(
        TextPosition(offset: endOffset < start ? start : endOffset),
      );
      return (
        render.localToGlobal(top.topLeft).dy,
        render.localToGlobal(bottom.bottomLeft).dy,
      );
    } catch (_) {
      return null;
    }
  }

  _Spot? _measure() {
    final render = _render;
    final box = context.findRenderObject();
    if (render == null || box is! RenderBox || !box.hasSize) return null;
    final touch = widget.hub.touch;
    final pos = touch ?? widget.hub.hover;
    final left = render.localToGlobal(Offset.zero).dx;
    widget.hub.zoneLeft = left - 52;
    widget.hub.zoneRight = left + 16;
    if (pos == null) return null;
    if (pos.dx < left - 52 || pos.dx > left + 16) return null;
    final editorTop = render.localToGlobal(Offset.zero).dy;
    if (pos.dy < editorTop || pos.dy > editorTop + render.size.height) {
      return null;
    }
    final lines = widget.folds.lines;
    final TextPosition at;
    try {
      at = render.getPositionForOffset(Offset(left + 4, pos.dy));
    } catch (_) {
      return null;
    }
    final i = lineAtOffset(lines, at.offset);
    if (i == null || lines[i].isFold) return null;
    final range = _lineRange(render, lines, i);
    if (range == null || pos.dy < range.$1 - 2 || pos.dy > range.$2 + 2) {
      return null;
    }
    // Centre on the line's first row.
    var start = 0;
    for (var k = 0; k < i; k++) {
      start += lines[k].length;
    }
    final rect = render.getLocalRectForCaret(TextPosition(offset: start));
    final centre = box.globalToLocal(render.localToGlobal(rect.center));
    final x = box.globalToLocal(Offset(left, 0)).dx;
    if (centre.dy < -_height || centre.dy > box.size.height + _height) {
      return null;
    }
    return _Spot(i, x, centre.dy);
  }

  // ---- Dragging ----

  void _dragStart(DragStartDetails d, _Spot spot) {
    final lines = widget.folds.lines;
    if (spot.line >= lines.length) return;
    _withSection = HardwareKeyboard.instance.isAltPressed;
    final (from, to) = blockSpan(lines, spot.line, withSection: _withSection);
    setState(() {
      _busy = true;
      _dragFrom = from;
      _dragTo = to;
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    final render = _render;
    final box = context.findRenderObject();
    if (render == null || box is! RenderBox) return;
    final lines = widget.folds.lines;
    final editorTop = render.localToGlobal(Offset.zero).dy;
    final y = d.globalPosition.dy.clamp(
      editorTop,
      editorTop + render.size.height,
    );
    final left = render.localToGlobal(Offset.zero).dx;
    final TextPosition at;
    try {
      at = render.getPositionForOffset(Offset(left + 4, y));
    } catch (_) {
      return;
    }
    var j = lineAtOffset(lines, at.offset);
    if (j == null) return;
    j = blockStart(lines, j);
    final span = blockSpan(lines, j);
    final top = _lineRange(render, lines, j);
    final bottom = _lineRange(render, lines, span.$2 - 1);
    if (top == null || bottom == null) return;
    final before = y < (top.$1 + bottom.$2) / 2;
    final dest = before ? j : span.$2;
    final lineY = before ? top.$1 : bottom.$2;
    setState(() {
      _dropAt = dest;
      _dropY = box.globalToLocal(Offset(0, lineY)).dy;
    });
  }

  void _dragEnd() {
    final from = _dragFrom, to = _dragTo, dest = _dropAt;
    setState(() {
      _busy = false;
      _dragFrom = _dragTo = _dropAt = _dropY = null;
    });
    if (from == null || to == null || dest == null) return;
    final lines = widget.folds.lines;
    final next = moveLines(lines, from, to, dest);
    if (next == null) return;
    final at = dest > to ? dest - (to - from) : dest;
    applyBlockEdit(widget.controller, lines, next, caretLine: at);
    widget.folds.documentChanged();
    widget.hub.clearTouch();
  }

  // ---- Menu ----

  Future<void> _menu(_Spot spot) async {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final l10n = context.l10n;
    final lines = widget.folds.lines;
    final i = spot.line;
    if (i >= lines.length) return;
    final line = lines[i];
    setState(() => _busy = true);
    final origin = box.localToGlobal(Offset(spot.x - _width, spot.y));
    RelativeRect position(BuildContext context) {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      return RelativeRect.fromRect(
        origin & const Size(_width, _height),
        Offset.zero & overlay.size,
      );
    }

    final dest = <int>[
      if (stepDestination(lines, i, -1) != null) -1,
      if (stepDestination(lines, i, 1) != null) 1,
    ];
    final choice = await showMenu<_Do>(
      context: context,
      position: position(context),
      items: [
        if (canTurnInto(line))
          PopupMenuItem(value: _Do.turn, child: Text(l10n.blocksTurnInto)),
        PopupMenuItem(value: _Do.duplicate, child: Text(l10n.blocksDuplicate)),
        PopupMenuItem(value: _Do.delete, child: Text(l10n.blocksDelete)),
        PopupMenuItem(
          value: _Do.up,
          enabled: dest.contains(-1),
          child: Text(l10n.blocksMoveUp),
        ),
        PopupMenuItem(
          value: _Do.down,
          enabled: dest.contains(1),
          child: Text(l10n.blocksMoveDown),
        ),
        if (widget.onCopyLink != null && !line.isFold)
          PopupMenuItem(value: _Do.link, child: Text(l10n.blocksCopyLink)),
      ],
    );
    if (!mounted) return;
    TurnInto? kind;
    if (choice == _Do.turn) {
      // ignore: use_build_context_synchronously
      kind = await showMenu<TurnInto>(
        context: context,
        position: position(context),
        items: [
          for (final k in TurnInto.values)
            PopupMenuItem(value: k, child: Text(_turnLabel(l10n, k))),
        ],
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final now = widget.folds.lines;
    if (i >= now.length) return;
    final (from, to) = blockSpan(now, i);
    switch (choice) {
      case _Do.turn:
        if (kind == null) break;
        final next = [...now];
        next[i] = turnLineInto(now[i], kind);
        applyBlockEdit(widget.controller, now, next, caretLine: i);
      case _Do.duplicate:
        applyBlockEdit(
          widget.controller,
          now,
          duplicateLines(now, from, to),
          caretLine: to,
        );
      case _Do.delete:
        applyBlockEdit(
          widget.controller,
          now,
          deleteLines(now, from, to),
          caretLine: from,
        );
      case _Do.up || _Do.down:
        final by = choice == _Do.up ? -1 : 1;
        final d = stepDestination(now, i, by);
        final next = d == null ? null : moveLines(now, from, to, d);
        if (d != null && next != null) {
          applyBlockEdit(
            widget.controller,
            now,
            next,
            caretLine: d > to ? d - (to - from) : d,
          );
        }
      case _Do.link:
        var start = 0;
        for (var k = 0; k < i; k++) {
          start += now[k].length;
        }
        await widget.onCopyLink?.call(start);
      case null:
        break;
    }
    widget.folds.documentChanged();
    widget.hub.clearTouch();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final duration = AppMotion.of(context, AppMotion.short);
    final shown = _spot ?? (_busy ? _last : null);
    final spot = shown ?? _last;
    return Stack(
      children: [
        if (spot != null)
          Positioned(
            left: (spot.x - 44).clamp(0, double.infinity),
            top: spot.y - _height / 2,
            width: _width,
            height: _height,
            child: IgnorePointer(
              ignoring: shown == null,
              child: AnimatedOpacity(
                opacity: shown == null ? 0 : 1,
                duration: duration,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _menu(spot),
                    onVerticalDragStart: (d) => _dragStart(d, spot),
                    onVerticalDragUpdate: _dragUpdate,
                    onVerticalDragEnd: (_) => _dragEnd(),
                    onVerticalDragCancel: _dragEnd,
                    child: Semantics(
                      button: true,
                      label: context.l10n.blocksHandleLabel,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: c.onSurfaceVariant.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_dropY != null)
          Positioned(
            left: (spot?.x ?? 0).clamp(0, double.infinity),
            right: 0,
            top: _dropY! - 1,
            height: 2,
            child: IgnorePointer(child: ColoredBox(color: c.primary)),
          ),
      ],
    );
  }
}

enum _Do { turn, duplicate, delete, up, down, link }

String _turnLabel(AppLocalizations l, TurnInto k) => switch (k) {
  TurnInto.text => l.blocksText,
  TurnInto.title => l.blocksTitle,
  TurnInto.heading => l.blocksHeading,
  TurnInto.subheading => l.blocksSubheading,
  TurnInto.bullet => l.blocksBulleted,
  TurnInto.numbered => l.blocksNumbered,
  TurnInto.checklist => l.blocksChecklist,
  TurnInto.quote => l.blocksQuote,
  TurnInto.code => l.blocksCode,
  TurnInto.callout => l.blocksCallout,
  TurnInto.toggle => l.blocksToggle,
};
