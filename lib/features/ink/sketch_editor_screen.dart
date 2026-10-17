import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'ink_canvas.dart';
import 'ink_model.dart';
import '../../theme/haptics.dart';
import 'pencil_taps.dart';

/// Drawn on light "paper" in both themes, like a real sheet, so ink colors
/// read the same everywhere a sketch is shown.
const sketchPaperColor = Color(0xFFFBFAF6);

const _penInks = [
  Color(0xFF2B2F2B), // graphite
  Color(0xFF55715A), // sage
  Color(0xFFA0664F), // clay
  Color(0xFF3F5F8A), // ink blue
];

const _highlighterInks = [
  Color(0xFFF2D66B), // butter
  Color(0xFF9CC79A), // sage
  Color(0xFFEBA9A4), // rose
  Color(0xFF9DC3DE), // mist blue
];

const _penWidths = [0.004, 0.007, 0.012];
const _highlighterWidth = 0.03;

enum _Tool { pen, highlighter, eraser }

/// Full-screen drawing for one sketch block. Pops with the edited [Sketch]
/// (also on system back / swipe), so leaving always keeps the drawing.
class SketchEditorScreen extends StatefulWidget {
  const SketchEditorScreen({super.key, required this.initial});

  final Sketch initial;

  @override
  State<SketchEditorScreen> createState() => _SketchEditorScreenState();
}

class _SketchEditorScreenState extends State<SketchEditorScreen> {
  // Shared across editor sessions: once a pen has been used, keep treating
  // fingers as palms for the rest of the app session.
  static final _policy = InkInputPolicy();

  late Sketch _sketch = widget.initial;
  final _undo = <Sketch>[];
  final _redo = <Sketch>[];

  _Tool _tool = _Tool.pen;
  _Tool _previousTool = _Tool.eraser;
  StreamSubscription<PencilAction>? _pencilTaps;
  int _penInk = 0;
  int _highlighterInk = 0;
  int _penWidth = 1;

  @override
  void initState() {
    super.initState();
    _pencilTaps = PencilTaps.instance.doubleTaps.listen(_onPencilTap);
  }

  @override
  void dispose() {
    _pencilTaps?.cancel();
    super.dispose();
  }

  void _setTool(_Tool tool) {
    if (tool == _tool) return;
    _previousTool = _tool;
    _tool = tool;
  }

  /// Double-tap on the Pencil, as configured in iPadOS Settings.
  void _onPencilTap(PencilAction action) {
    if (action != PencilAction.ignore) AppHaptics.selection();
    setState(() => _applyPencilTap(action));
  }

  void _applyPencilTap(PencilAction action) {
    switch (action) {
      case PencilAction.switchEraser:
        _setTool(_tool == _Tool.eraser ? _previousTool : _Tool.eraser);
      case PencilAction.switchPrevious:
        _setTool(_previousTool);
      case PencilAction.showColorPalette:
        // There's one row of inks; the tap steps to the next one.
        if (_tool == _Tool.highlighter) {
          _highlighterInk = (_highlighterInk + 1) % _highlighterInks.length;
        } else if (_tool == _Tool.pen) {
          _penInk = (_penInk + 1) % _penInks.length;
        }
      case PencilAction.ignore:
        break;
    }
  }

  void _beginChange() {
    _undo.add(_sketch);
    _redo.clear();
  }

  void _undoLast() => setState(() {
    _redo.add(_sketch);
    _sketch = _undo.removeLast();
  });

  void _redoLast() => setState(() {
    _undo.add(_sketch);
    _sketch = _redo.removeLast();
  });

  void _moreSpace() => setState(() {
    _beginChange();
    _sketch = _sketch.copyWith(
      aspect: math.min(Sketch.maxAspect, _sketch.aspect + 0.5),
    );
  });

  void _done() => Navigator.of(context).pop(_sketch);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final desktop = isDesktop(context);
    _policy.mouseAlwaysDraws = desktop;
    final fingersDraw = _policy.fingersDraw;

    return CallbackShortcuts(
      bindings: {
        for (final meta in const [true, false])
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: meta,
            control: !meta,
          ): () {
            if (_undo.isNotEmpty) _undoLast();
          },
        for (final meta in const [true, false])
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: meta,
            control: !meta,
            shift: true,
          ): () {
            if (_redo.isNotEmpty) _redoLast();
          },
      },
      child: Focus(autofocus: true, child: _buildEditor(c, fingersDraw)),
    );
  }

  Widget _buildEditor(ColorScheme c, bool fingersDraw) {
    final desktop = isDesktop(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        backgroundColor: c.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: c.surfaceContainerLow,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Done',
            onPressed: _done,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _undo.isEmpty ? null : _undoLast,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
              onPressed: _redo.isEmpty ? null : _redoLast,
            ),
            // A mouse or trackpad always draws on a desktop; the finger
            // switch is for touch screens.
            if (!desktop)
              IconButton(
                isSelected: fingersDraw,
                icon: const Icon(Icons.pan_tool_outlined),
                selectedIcon: const Icon(Icons.gesture),
                tooltip: fingersDraw
                    ? 'Fingers draw (tap to scroll with fingers instead)'
                    : 'Fingers scroll (tap to draw with fingers)',
                onPressed: () =>
                    setState(() => _policy.fingerDrawsOverride = !fingersDraw),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: _done,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          // While fingers draw, a finger drag must not also scroll.
          physics: fingersDraw && !desktop
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: sketchPaperColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.outlineVariant),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: _DotGridPainter(),
                        child: InkCanvas(
                          sketch: _sketch,
                          policy: _policy,
                          tool: _tool == _Tool.highlighter
                              ? InkTool.highlighter
                              : InkTool.pen,
                          color: _tool == _Tool.highlighter
                              ? _highlighterInks[_highlighterInk]
                              : _penInks[_penInk],
                          width: _tool == _Tool.highlighter
                              ? _highlighterWidth
                              : _penWidths[_penWidth],
                          erasing: _tool == _Tool.eraser,
                          onGestureStart: _beginChange,
                          onChanged: (s) => setState(() => _sketch = s),
                          onPolicyChanged: () => setState(() {}),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_sketch.aspect < Sketch.maxAspect)
                    TextButton.icon(
                      icon: const Icon(Icons.expand_more),
                      label: const Text('More space'),
                      onPressed: _moreSpace,
                    ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _Palette(
          tool: _tool,
          inks: _tool == _Tool.highlighter ? _highlighterInks : _penInks,
          ink: _tool == _Tool.highlighter ? _highlighterInk : _penInk,
          penWidth: _penWidth,
          onTool: (t) => setState(() => _setTool(t)),
          onInk: (i) => setState(() {
            if (_tool == _Tool.highlighter) {
              _highlighterInk = i;
            } else {
              _penInk = i;
              _tool = _Tool.pen;
            }
          }),
          onPenWidth: (w) => setState(() {
            _penWidth = w;
            _tool = _Tool.pen;
          }),
        ),
      ),
    );
  }
}

/// The floating tool palette: pen / highlighter / eraser, inks, and (for
/// the pen) three thicknesses.
class _Palette extends StatelessWidget {
  const _Palette({
    required this.tool,
    required this.inks,
    required this.ink,
    required this.penWidth,
    required this.onTool,
    required this.onInk,
    required this.onPenWidth,
  });

  final _Tool tool;
  final List<Color> inks;
  final int ink;
  final int penWidth;
  final ValueChanged<_Tool> onTool;
  final ValueChanged<int> onInk;
  final ValueChanged<int> onPenWidth;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    Widget toolButton(_Tool t, IconData icon, String label) => IconButton(
      isSelected: tool == t,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: tool == t ? c.primaryContainer : null,
        foregroundColor: tool == t ? c.onPrimaryContainer : c.onSurfaceVariant,
      ),
      icon: Icon(icon),
      tooltip: label,
      onPressed: () => onTool(t),
    );

    return Material(
      color: c.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolButton(_Tool.pen, Icons.edit_outlined, 'Pen'),
              toolButton(
                _Tool.highlighter,
                Icons.border_color_outlined,
                'Highlighter',
              ),
              toolButton(
                _Tool.eraser,
                Icons.cleaning_services_outlined,
                'Eraser',
              ),
              AnimatedSize(
                duration: AppMotion.medium,
                curve: AppMotion.standard,
                child: tool == _Tool.eraser
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 4),
                          Container(
                            width: 1,
                            height: 28,
                            color: c.outlineVariant,
                          ),
                          const SizedBox(width: 4),
                          for (var i = 0; i < inks.length; i++)
                            _Swatch(
                              color: inks[i],
                              selected: i == ink,
                              onTap: () => onInk(i),
                            ),
                          if (tool == _Tool.pen) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 1,
                              height: 28,
                              color: c.outlineVariant,
                            ),
                            const SizedBox(width: 4),
                            for (var i = 0; i < _penWidths.length; i++)
                              _WidthDot(
                                size: 6.0 + i * 5,
                                selected: i == penWidth,
                                onTap: () => onPenWidth(i),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ink color',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.short,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? c.primary : c.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Line thickness',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primaryContainer : null,
            shape: BoxShape.circle,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? c.onPrimaryContainer : c.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint dot grid, like dotted notebook paper.
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x1F2B2F2B);
    final step = size.width / 24;
    for (var y = step; y < size.height; y += step) {
      for (var x = step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
