import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';
import '../notes/note_editor_screen.dart';
import 'annotations_providers.dart';

const _highlightColors = [
  Color(0xFFFFEB3B), // yellow
  Color(0xFF69F0AE), // green
  Color(0xFFFF80AB), // pink
  Color(0xFF80D8FF), // blue
];

/// Views a paper's PDF with freeform highlighter annotation. Tap the pen
/// icon to toggle drawing mode; while off, the viewer pans/zooms normally.
class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.paperId,
    required this.pdfPath,
  });

  final String paperId;
  final String pdfPath;

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final _repaintKey = GlobalKey();
  bool _highlightMode = false;
  Color _color = _highlightColors.first;
  bool _extracting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          ..._highlightColors.map(
            (c) => GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c == _color
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_highlightMode ? Icons.edit : Icons.edit_outlined),
            tooltip: _highlightMode ? 'Stop highlighting' : 'Highlight',
            onPressed: () => setState(() => _highlightMode = !_highlightMode),
          ),
          IconButton(
            icon: _extracting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.note_add_outlined),
            tooltip: 'Extract view to a note',
            onPressed: _extracting ? null : _extractToNote,
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _repaintKey,
        child: PdfViewer.file(
          widget.pdfPath,
          params: PdfViewerParams(
            pageOverlaysBuilder: (context, pageRectInViewer, page) {
              return [
                _PageHighlightOverlay(
                  paperId: widget.paperId,
                  pageNumber: page.pageNumber,
                  pageRect: pageRectInViewer,
                  highlightMode: _highlightMode,
                  color: _color,
                ),
              ];
            },
          ),
        ),
      ),
    );
  }

  Future<void> _extractToNote() async {
    setState(() => _extracting = true);
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final path = await saveBytesToAppStorage(
        bytes,
        'attachments',
        'highlight.png',
      );

      final db = ref.read(databaseProvider);
      final paper = await (db.select(
        db.papers,
      )..where((p) => p.id.equals(widget.paperId))).getSingle();

      final noteId = const Uuid().v4();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: Value(noteId),
          title: Value('Highlight from ${paper.title}'),
        ),
      );
      await db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          noteId: Value(noteId),
          type: AttachmentType.image,
          path: Value(path),
        ),
      );
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: noteId, paperId: widget.paperId));

      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }
}

class _PageHighlightOverlay extends ConsumerStatefulWidget {
  const _PageHighlightOverlay({
    required this.paperId,
    required this.pageNumber,
    required this.pageRect,
    required this.highlightMode,
    required this.color,
  });

  final String paperId;
  final int pageNumber;
  final Rect pageRect;
  final bool highlightMode;
  final Color color;

  @override
  ConsumerState<_PageHighlightOverlay> createState() =>
      _PageHighlightOverlayState();
}

class _PageHighlightOverlayState
    extends ConsumerState<_PageHighlightOverlay> {
  List<Offset>? _liveStroke;

  Offset _normalize(Offset local) =>
      Offset(local.dx / widget.pageRect.width, local.dy / widget.pageRect.height);

  @override
  Widget build(BuildContext context) {
    final annotationsAsync = ref.watch(
      annotationsForPageProvider((
        paperId: widget.paperId,
        pageNumber: widget.pageNumber,
      )),
    );
    final saved = annotationsAsync.value ?? const [];

    return SizedBox(
      width: widget.pageRect.width,
      height: widget.pageRect.height,
      child: IgnorePointer(
        ignoring: !widget.highlightMode,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => setState(() => _liveStroke = [_normalize(d.localPosition)]),
          onPanUpdate: (d) =>
              setState(() => _liveStroke!.add(_normalize(d.localPosition))),
          onPanEnd: (_) => _commitStroke(),
          child: CustomPaint(
            size: widget.pageRect.size,
            painter: _HighlightPainter(
              saved: saved,
              live: _liveStroke,
              liveColor: widget.color,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _commitStroke() async {
    final stroke = _liveStroke;
    setState(() => _liveStroke = null);
    if (stroke == null) return;
    await saveHighlightStroke(
      ref.read(databaseProvider),
      paperId: widget.paperId,
      pageNumber: widget.pageNumber,
      normalizedPoints: stroke,
      color: widget.color,
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.saved, this.live, required this.liveColor});

  final List<Annotation> saved;
  final List<Offset>? live;
  final Color liveColor;

  void _paintStroke(Canvas canvas, Size size, List<Offset> normalized, Color color) {
    if (normalized.length < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = size.width * 0.025
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(normalized.first.dx * size.width, normalized.first.dy * size.height);
    for (final point in normalized.skip(1)) {
      path.lineTo(point.dx * size.width, point.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in saved) {
      _paintStroke(
        canvas,
        size,
        decodeStrokePoints(annotation.pointsJson),
        colorFromHex(annotation.colorHex),
      );
    }
    if (live != null) _paintStroke(canvas, size, live!, liveColor);
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) =>
      oldDelegate.saved != saved || oldDelegate.live != live;
}
