import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/motion_widgets.dart';
import '../projects/open_from_page.dart';
import 'graph_model.dart';

/// The map: notes (circles) and papers (rounded squares) joined by the links
/// between them. Pan and zoom; tap a node to open it. [projectId] limits it
/// to one project's items. Nodes with no connections are hidden until asked
/// for.
class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key, this.projectId, this.title = 'Map'});

  final String? projectId;
  final String title;

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  final _controller = TransformationController();
  var _showIsolated = false;
  Object? _fittedFor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(GraphNode node) {
    if (node.kind == GraphNodeKind.note) {
      openNoteFromPage(context, ref, node.id);
    } else {
      openPaperFromPage(context, ref, node.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(graphLayoutProvider(widget.projectId));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_showIsolated ? Icons.blur_on : Icons.blur_off),
            tooltip: _showIsolated
                ? 'Hide unconnected items'
                : 'Show unconnected items',
            onPressed: () => setState(() => _showIsolated = !_showIsolated),
          ),
        ],
      ),
      body: StateSwitcher(
        stateKey: layout.hasValue ? 'ready' : 'loading',
        child: layout.when(
          loading: () => const SizedBox.expand(),
          error: (e, _) => const EmptyState(
            icon: Icons.error_outline,
            title: 'Couldn’t draw the map',
            message: 'Try again in a moment.',
          ),
          data: (l) => _view(context, l),
        ),
      ),
    );
  }

  Widget _view(BuildContext context, GraphLayout layout) {
    final data = layout.data;
    final visible = [
      for (var i = 0; i < data.nodes.length; i++)
        if (_showIsolated || data.degrees[i] > 0) i,
    ];
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.hub_outlined,
        title: data.nodes.isEmpty ? 'Nothing to map yet' : 'Nothing connected',
        message:
            'Link notes to each other or to papers, or cite a paper with '
            '[@, and the connections appear here.',
      );
    }
    final hasConnected = data.degrees.any((d) => d > 0);
    final canvas = Size(
      layout.size.width,
      _showIsolated || !hasConnected ? layout.size.height : layout.size.width,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final fitKey = (widget.projectId, _showIsolated, layout, box.biggest);
        if (_fittedFor != fitKey) {
          _fittedFor = fitKey;
          final scale = math.min(
            box.maxWidth / canvas.width,
            box.maxHeight / canvas.height,
          );
          final dx = (box.maxWidth - canvas.width * scale) / 2;
          final dy = (box.maxHeight - canvas.height * scale) / 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _controller.value = Matrix4.identity()
              ..translateByDouble(dx, dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1);
          });
        }
        return InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          minScale: 0.05,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(2000),
          child: GraphCanvas(
            key: const ValueKey('graph-canvas'),
            layout: layout,
            visible: visible,
            size: canvas,
            onTapNode: (i) => _open(data.nodes[i]),
          ),
        );
      },
    );
  }
}

double nodeRadius(int degree) => math.min(5 + 2.2 * math.sqrt(degree), 18);

/// Draws and hit-tests the graph at its own size; the parent pans/zooms it.
class GraphCanvas extends StatelessWidget {
  const GraphCanvas({
    super.key,
    required this.layout,
    required this.visible,
    required this.size,
    required this.onTapNode,
  });

  final GraphLayout layout;
  final List<int> visible;
  final Size size;
  final ValueChanged<int> onTapNode;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall!
        .copyWith(color: c.onSurfaceVariant);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        int? best;
        var bestDistance = double.infinity;
        for (final i in visible) {
          final dist = (layout.positions[i] - d.localPosition).distance;
          final reach = nodeRadius(layout.data.degrees[i]) + 10;
          if (dist <= reach && dist < bestDistance) {
            best = i;
            bestDistance = dist;
          }
        }
        if (best != null) onTapNode(best);
      },
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: _GraphPainter(
            layout: layout,
            visible: visible,
            noteColor: c.primary,
            paperColor: c.tertiary,
            edgeColor: c.outlineVariant,
            labelStyle: labelStyle,
            direction: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
  const dash = 5.0, gap = 4.0;
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = (b - a) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.layout,
    required this.visible,
    required this.noteColor,
    required this.paperColor,
    required this.edgeColor,
    required this.labelStyle,
    required this.direction,
  });

  final GraphLayout layout;
  final List<int> visible;
  final Color noteColor;
  final Color paperColor;
  final Color edgeColor;
  final TextStyle labelStyle;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final data = layout.data;
    final shown = visible.toSet();
    final edgePaint = Paint()
      ..color = edgeColor
      ..strokeWidth = 1.2;
    // Citations: dashed and fainter than links, in the paper colour.
    final citePaint = Paint()
      ..color = paperColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final e in data.edges) {
      final (a, b) = e;
      if (!shown.contains(a) || !shown.contains(b)) continue;
      if (data.citationEdges.contains(e)) {
        _dashedLine(
          canvas,
          layout.positions[a],
          layout.positions[b],
          citePaint,
        );
      } else {
        canvas.drawLine(layout.positions[a], layout.positions[b], edgePaint);
      }
    }
    final labelAll = visible.length <= 80;
    for (final i in visible) {
      final node = data.nodes[i];
      final p = layout.positions[i];
      final r = nodeRadius(data.degrees[i]);
      if (node.kind == GraphNodeKind.note) {
        canvas.drawCircle(p, r, Paint()..color = noteColor);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: p, width: r * 1.9, height: r * 1.9),
            Radius.circular(r * 0.35),
          ),
          Paint()..color = paperColor,
        );
      }
      if (labelAll || data.degrees[i] >= 3) {
        final tp = TextPainter(
          text: TextSpan(text: node.label, style: labelStyle),
          textDirection: direction,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 120);
        tp.paint(canvas, p + Offset(-tp.width / 2, r + 3));
        tp.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.layout != layout ||
      old.visible.length != visible.length ||
      old.noteColor != noteColor ||
      old.paperColor != paperColor ||
      old.edgeColor != edgeColor;
}
