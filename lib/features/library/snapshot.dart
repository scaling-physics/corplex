import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/local_files.dart';
import '../../data/tables/attachments_table.dart';
import '../notes/note_content.dart';
import 'highlights.dart';

/// The part of [image] under [area] (in logical pixels of the captured
/// widget, which [image] renders at [pixelRatio]), as a PNG.
Future<Uint8List> cropToPng(
  ui.Image image,
  Rect area,
  double pixelRatio,
) async {
  final bounds =
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble());
  final src = Rect.fromLTRB(
    area.left * pixelRatio,
    area.top * pixelRatio,
    area.right * pixelRatio,
    area.bottom * pixelRatio,
  ).intersect(bounds);
  final width = src.width.round().clamp(1, image.width);
  final height = src.height.round().clamp(1, image.height);

  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final cropped = await recorder.endRecording().toImage(width, height);
  try {
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    cropped.dispose();
  }
}

/// Makes a note holding [png] (a figure or table snapped from a paper),
/// with a "From p. N" link back to the page, linked to the paper. Returns
/// the note's id.
Future<String> createSnapshotNote(
  AppDatabase db, {
  required String paperId,
  required int page,
  required Uint8List png,
}) async {
  final path = await saveBytesToAppStorage(png, 'attachments', 'figure.png');
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(paperId))).getSingle();

  final content = Document();
  final label = 'p. $page';
  content.insert(0, 'From $label');
  content.format(5, label.length, LinkAttribute(paperPageLink(paperId, page)));

  final noteId = const Uuid().v4();
  await db.transaction(() async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(noteId),
            title: Value('Figure from ${paper.title}, p. $page'),
            content: Value(encodeNoteContent(content)),
          ),
        );
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            noteId: Value(noteId),
            type: AttachmentType.image,
            path: Value(path),
          ),
        );
    await db
        .into(db.notePaperRefs)
        .insert(
          NotePaperRefsCompanion.insert(noteId: noteId, paperId: paperId),
        );
  });
  return noteId;
}

/// Covers the reader while choosing what to snapshot: drag a box around a
/// figure or table, or take the whole view.
class SnapshotOverlay extends StatefulWidget {
  const SnapshotOverlay({
    super.key,
    required this.onSelected,
    required this.onCancel,
  });

  /// The chosen area, in this overlay's coordinates; null means the
  /// whole view.
  final ValueChanged<Rect?> onSelected;
  final VoidCallback onCancel;

  /// A box smaller than this on either side is taken as a slip, not a
  /// choice.
  static const minSide = 24.0;

  @override
  State<SnapshotOverlay> createState() => _SnapshotOverlayState();
}

class _SnapshotOverlayState extends State<SnapshotOverlay> {
  Offset? _start;
  Rect? _box;

  void _end() {
    final box = _box;
    setState(() {
      _start = null;
      _box = null;
    });
    if (box == null ||
        box.width < SnapshotOverlay.minSide ||
        box.height < SnapshotOverlay.minSide) {
      return;
    }
    widget.onSelected(box);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => setState(() {
            _start = d.localPosition;
            _box = Rect.fromPoints(d.localPosition, d.localPosition);
          }),
          onPanUpdate: (d) =>
              setState(() => _box = Rect.fromPoints(_start!, d.localPosition)),
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: CustomPaint(
            painter: _BoxPainter(
              box: _box,
              shade: c.scrim.withValues(alpha: 0.32),
              edge: c.primary,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Center(
            child: Material(
              color: c.surfaceContainerHigh,
              elevation: 2,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Drag around a figure or table',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => widget.onSelected(null),
                      child: const Text('Whole view'),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close),
                      onPressed: widget.onCancel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({required this.box, required this.shade, required this.edge});

  final Rect? box;
  final Color shade;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    final box = this.box;
    if (box == null) {
      canvas.drawRect(whole, Paint()..color = shade);
      return;
    }
    // Shade everything but the box, so the chosen area reads as lit.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(whole),
        Path()..addRect(box),
      ),
      Paint()..color = shade,
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.box != box || old.shade != shade || old.edge != edge;
}
