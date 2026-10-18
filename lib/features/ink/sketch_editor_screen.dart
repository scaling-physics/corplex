import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/mac_window.dart' show isDesktop;
import 'ink_canvas.dart';
import 'ink_model.dart';
import 'ink_tools.dart';
import '../../theme/haptics.dart';
import 'pencil_taps.dart';

export 'ink_tools.dart' show sketchPaperColor;

/// Full-screen drawing for one sketch block — "Expand" from a drawing in a
/// note, for a big diagram on a small screen. Pops with the edited [Sketch]
/// (also on system back / swipe), so leaving always keeps the drawing.
class SketchEditorScreen extends StatefulWidget {
  const SketchEditorScreen({super.key, required this.initial, this.tools});

  final Sketch initial;

  /// The note's tools, so the pen, ink and thickness carry over; a fresh
  /// set when null.
  final InkTools? tools;

  @override
  State<SketchEditorScreen> createState() => _SketchEditorScreenState();
}

class _SketchEditorScreenState extends State<SketchEditorScreen> {
  late Sketch _sketch = widget.initial;
  final _undo = <Sketch>[];
  final _redo = <Sketch>[];

  late final InkTools _tools = widget.tools ?? InkTools();
  StreamSubscription<PencilAction>? _pencilTaps;

  @override
  void initState() {
    super.initState();
    _tools.addListener(_toolsChanged);
    _pencilTaps = PencilTaps.instance.doubleTaps.listen(_onPencilTap);
  }

  @override
  void dispose() {
    _pencilTaps?.cancel();
    _tools.removeListener(_toolsChanged);
    if (widget.tools == null) _tools.dispose();
    super.dispose();
  }

  void _toolsChanged() => setState(() {});

  /// Double-tap on the Pencil, as configured in iPadOS Settings.
  void _onPencilTap(PencilAction action) {
    if (action != PencilAction.ignore) AppHaptics.selection();
    _tools.applyPencilTap(action);
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
    inkPolicy.mouseAlwaysDraws = desktop;
    final fingersDraw = inkPolicy.fingersDraw;

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
                onPressed: () => setState(
                  () => inkPolicy.fingerDrawsOverride = !fingersDraw,
                ),
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
                          policy: inkPolicy,
                          tool: _tools.inkTool,
                          color: _tools.color,
                          width: _tools.width,
                          erasing: _tools.erasing,
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
        floatingActionButton: InkPalette(tools: _tools),
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
