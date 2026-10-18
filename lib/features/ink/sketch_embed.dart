import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/app_theme.dart';
import 'ink_canvas.dart';
import 'ink_model.dart';
import 'ink_painter.dart';
import 'ink_session.dart';
import 'sketch_editor_screen.dart';

export 'ink_session.dart'
    show sketchEmbedType, emptySketchData, sketchOffsetNear, sketchAt;

/// Renders a drawing block in the note. In an editor with an [InkSession]
/// it is drawn on in place (see [InkSession]); anywhere else (read-only
/// views) it is a picture that opens full screen on tap.
class SketchEmbedBuilder extends EmbedBuilder {
  const SketchEmbedBuilder();

  @override
  String get key => sketchEmbedType;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final session = InkSessionScope.maybeOf(context);
    if (session != null && !embedContext.readOnly) {
      return InlineSketch(node: embedContext.node, session: session);
    }
    return _StaticSketch(embedContext: embedContext);
  }
}

/// A drawing in an open note, drawn on where it sits.
class InlineSketch extends StatefulWidget {
  const InlineSketch({super.key, required this.node, required this.session});

  final Embed node;
  final InkSession session;

  @override
  State<InlineSketch> createState() => _InlineSketchState();
}

class _InlineSketchState extends State<InlineSketch> implements InlineDrawing {
  final _paperKey = GlobalKey();
  String? _decodedFrom;
  Sketch _sketch = const Sketch();

  /// The height being dragged with the handle, until it's let go.
  double? _dragAspect;

  @override
  int get offset => widget.node.documentOffset;

  @override
  Sketch get sketch {
    final data = widget.node.value.data as String;
    if (data != _decodedFrom) {
      _decodedFrom = data;
      _sketch = Sketch.decode(data);
    }
    return _sketch;
  }

  @override
  Rect? get globalRect {
    final box = _paperKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    widget.session.drawings.add(this);
  }

  @override
  void didUpdateWidget(InlineSketch old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.drawings.remove(this);
      widget.session.drawings.add(this);
    }
  }

  @override
  void dispose() {
    widget.session.drawings.remove(this);
    super.dispose();
  }

  void _startInk() {
    widget.session.activate(offset);
    widget.session.onInkStart?.call();
  }

  /// The handle's lowest allowed height: just below the lowest stroke.
  double get _minAspect {
    final lowest = sketch.strokes.fold<double>(
      0,
      (m, s) => math.max(m, s.bottom),
    );
    return math.max(0.12, lowest + 0.02);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final c = Theme.of(context).colorScheme;
    final active = session.isActive(offset);
    final sketch = this.sketch;
    final shown = _dragAspect == null
        ? sketch
        : sketch.copyWith(aspect: _dragAspect);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: 'Drawing',
        button: !active,
        child: GestureDetector(
          // A tap with a finger or mouse chooses the drawing (a pen draws
          // on it straight away and never needs to).
          onTap: active
              ? null
              : () {
                  session.activate(offset);
                  // The editor takes the tap too and focuses; drawing
                  // wants the keyboard out of the way.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => session.onInkStart?.call(),
                  );
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                key: _paperKey,
                duration: AppMotion.of(context, AppMotion.short),
                decoration: BoxDecoration(
                  color: sketchPaperColor,
                  borderRadius: BorderRadius.circular(12),
                  // Unchosen, a drawing blends into a light page like ink
                  // on the paper; on a dark page its light sheet keeps a
                  // faint edge.
                  border: Border.all(
                    color: active
                        ? c.primary
                        : Theme.of(context).brightness == Brightness.dark
                        ? c.outlineVariant
                        : Colors.transparent,
                    width: active ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    InkCanvas(
                      sketch: shown,
                      policy: inkPolicy,
                      tool: session.inkTool,
                      color: session.color,
                      width: session.width,
                      erasing: session.erasing,
                      othersDraw: active,
                      onGestureStart: _startInk,
                      onChanged: (s) => session.write(offset, s),
                      onPolicyChanged: () => setState(() {}),
                    ),
                    if (sketch.isEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              active ? 'Draw here' : 'Tap to draw',
                              style: TextStyle(color: c.outline),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (active)
                _ResizeHandle(
                  onDrag: (dy, width) => setState(() {
                    final from = _dragAspect ?? sketch.aspect;
                    _dragAspect = (from + dy / width).clamp(
                      _minAspect,
                      Sketch.maxAspect,
                    );
                  }),
                  onEnd: () {
                    final aspect = _dragAspect;
                    setState(() => _dragAspect = null);
                    if (aspect != null && aspect != sketch.aspect) {
                      session.write(offset, sketch.copyWith(aspect: aspect));
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The grip under a chosen drawing: drag it to make the drawing taller or
/// shorter (never cutting off ink).
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag, required this.onEnd});

  final void Function(double dy, double width) onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey('sketch-resize'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => onDrag(d.delta.dy, box.maxWidth),
          onVerticalDragEnd: (_) => onEnd(),
          child: SizedBox(
            height: 22,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A drawing where there's no ink session (read-only): the picture, which
/// opens full screen on tap when the document can still be edited.
class _StaticSketch extends StatelessWidget {
  const _StaticSketch({required this.embedContext});

  final EmbedContext embedContext;

  @override
  Widget build(BuildContext context) {
    final sketch = Sketch.decode(embedContext.node.value.data as String);
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: 'Drawing',
        child: GestureDetector(
          onTap: embedContext.readOnly ? null : () => _edit(context, sketch),
          child: Container(
            decoration: BoxDecoration(
              color: sketchPaperColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 1 / sketch.aspect,
              child: CustomPaint(painter: InkPainter(strokes: sketch.strokes)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Sketch sketch) async {
    final controller = embedContext.controller;
    final offset = embedContext.node.documentOffset;
    final edited = await Navigator.of(context).push<Sketch>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SketchEditorScreen(initial: sketch),
      ),
    );
    if (edited == null) return;
    if (sketchOffsetNear(controller.document, offset) != offset) return;
    controller.replaceText(
      offset,
      1,
      CustomBlockEmbed(sketchEmbedType, edited.encode()),
      null,
    );
  }
}
