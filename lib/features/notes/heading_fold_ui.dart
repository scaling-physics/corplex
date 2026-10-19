import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart' show Operation;

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import 'heading_fold.dart';
import 'heading_fold_controller.dart';

/// Puts a [HeadingFolds] where the fold embed (and its tap) can find it.
class HeadingFoldScope extends InheritedWidget {
  const HeadingFoldScope({
    super.key,
    required this.folds,
    required super.child,
  });

  final HeadingFolds folds;

  static HeadingFolds? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeadingFoldScope>()?.folds;

  @override
  bool updateShouldNotify(HeadingFoldScope old) => folds != old.folds;
}

/// What a collapsed section looks like in the note: a quiet "…" under its
/// heading. Tapping it opens the section.
class FoldEmbedBuilder extends EmbedBuilder {
  const FoldEmbedBuilder();

  @override
  String get key => foldEmbedType;

  @override
  bool get expanded => true;

  /// Copying a "…" copies the text it stands for.
  @override
  String toPlainText(Embed node) {
    final data = node.value.data;
    if (data is! String) return '';
    final b = StringBuffer();
    for (final line in expandLines([
      FoldLine([
        Operation.insert({foldEmbedType: data}),
      ], null),
    ])) {
      b
        ..write(line.text)
        ..write('\n');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final folds = HeadingFoldScope.maybeOf(context);
    final offset = embedContext.node.documentOffset;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final label = context.l10n.foldShowSection;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: folds != null,
        label: label,
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: folds == null || embedContext.readOnly
                ? null
                : () => folds.expandFoldAt(offset),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Icon(Icons.more_horiz, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chevrons in the left margin of a note's headings, drawn over the
/// page rather than inside Quill's lines: one on the heading the pointer is
/// over, on the heading the caret is in, and (turned) on every collapsed
/// heading. Tapping one folds or opens its section.
///
/// Place it over the page's scroll view, filling the same box. It only
/// catches touches on the chevrons themselves.
class HeadingChevrons extends StatefulWidget {
  const HeadingChevrons({
    super.key,
    required this.folds,
    required this.controller,
    required this.editorKey,
    required this.scroll,
    required this.hoverY,
  });

  final HeadingFolds folds;
  final QuillController controller;
  final GlobalKey<EditorState> editorKey;
  final ScrollController scroll;

  /// The pointer's vertical position in global coordinates while it is over
  /// the page (null otherwise).
  final ValueNotifier<double?> hoverY;

  @override
  State<HeadingChevrons> createState() => _HeadingChevronsState();
}

class _Spot {
  const _Spot(this.heading, this.x, this.y);
  final LiveHeading heading;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is _Spot &&
      other.heading.offset == heading.offset &&
      other.heading.folded == heading.folded &&
      other.heading.line == heading.line &&
      (other.x - x).abs() < 0.5 &&
      (other.y - y).abs() < 0.5;

  @override
  int get hashCode => Object.hash(heading.offset, heading.folded);
}

class _HeadingChevronsState extends State<HeadingChevrons> {
  static const _width = 24.0;
  static const _height = 32.0;

  List<_Spot> _spots = const [];
  late final Listenable _merged = Listenable.merge([
    widget.folds,
    widget.controller,
    widget.scroll,
    widget.hoverY,
  ]);

  @override
  void initState() {
    super.initState();
    _merged.addListener(_changed);
    _measureAfterFrame();
  }

  @override
  void dispose() {
    _merged.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _measureAfterFrame();
  }

  void _measureAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _measure();
      if (!_same(next, _spots)) setState(() => _spots = next);
    });
  }

  static bool _same(List<_Spot> a, List<_Spot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<_Spot> _measure() {
    final render = widget.editorKey.currentState?.renderEditor;
    final box = context.findRenderObject();
    if (render == null || !render.attached || box is! RenderBox) {
      return const [];
    }
    if (!box.hasSize) return const [];
    final left = box.globalToLocal(render.localToGlobal(Offset.zero)).dx;
    final out = <_Spot>[];
    for (final h in widget.folds.headings()) {
      final Rect rect;
      try {
        rect = render.getLocalRectForCaret(TextPosition(offset: h.offset));
      } catch (_) {
        continue; // not laid out yet
      }
      final y = box.globalToLocal(render.localToGlobal(rect.center)).dy;
      if (y < -_height || y > box.size.height + _height) continue;
      out.add(_Spot(h, left, y));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final duration = AppMotion.of(context, AppMotion.short);
    final box = context.findRenderObject();
    final hover = widget.hoverY.value;
    final hoverLocal = hover != null && box is RenderBox && box.hasSize
        ? box.globalToLocal(Offset(0, hover)).dy
        : null;
    final sel = widget.controller.selection;
    final caret = sel.isValid && sel.isCollapsed ? sel.baseOffset : null;
    return Stack(
      children: [
        for (final s in _spots)
          Positioned(
            left: (s.x - _width).clamp(0, double.infinity),
            top: s.y - _height / 2,
            width: _width,
            height: _height,
            child: _Chevron(
              key: ValueKey(s.heading.offset),
              folded: s.heading.folded,
              visible:
                  s.heading.folded ||
                  (hoverLocal != null &&
                      (hoverLocal - s.y).abs() <= _height / 2) ||
                  (caret != null &&
                      caret >= s.heading.offset &&
                      caret < s.heading.offset + s.heading.length),
              duration: duration,
              color: c.onSurfaceVariant,
              tooltip: s.heading.folded
                  ? l10n.foldExpandSection
                  : l10n.foldCollapseSection,
              onTap: () => widget.folds.toggleHeading(s.heading.line),
            ),
          ),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    super.key,
    required this.folded,
    required this.visible,
    required this.duration,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final bool folded;
  final bool visible;
  final Duration duration;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        child: Tooltip(
          message: tooltip,
          child: InkResponse(
            radius: 16,
            onTap: onTap,
            child: Center(
              child: AnimatedRotation(
                turns: folded ? 0 : 0.25,
                duration: duration,
                child: Icon(Icons.chevron_right, size: 20, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
