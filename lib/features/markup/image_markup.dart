import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../../data/database.dart';
import '../../data/local_files.dart';
import '../ink/ink_model.dart';
import '../ink/ink_painter.dart';

/// Marking up an image keeps the marks editable. The attachment row points
/// at a *composite* PNG (image + strokes) so every other place that shows
/// images, exports and syncs just works. Next to the composite sits a
/// sidecar `<name>.markup.json` holding the path of the untouched original
/// and the strokes, so "Mark up" again reopens the original with its marks
/// rather than baking them in. The original stays on disk (it is not synced:
/// only the composite is the attachment); re-saving replaces the previous
/// composite and sidecar.
class MarkupSource {
  const MarkupSource({required this.originalPath, required this.sketch});

  final String originalPath;

  /// Strokes in image-width units; `aspect` is image height / width.
  final Sketch? sketch;
}

String markupSidecarPath(String compositePath) =>
    '${p.withoutExtension(compositePath)}.markup.json';

/// What to open for [path]: the original and earlier strokes when [path] is
/// a composite this feature wrote, else [path] itself and no strokes.
Future<MarkupSource> loadMarkupSource(String path) async {
  final side = File(markupSidecarPath(path));
  try {
    if (await side.exists()) {
      final json = jsonDecode(await side.readAsString()) as Map;
      final original = json['original'] as String;
      if (await File(original).exists()) {
        return MarkupSource(
          originalPath: original,
          sketch: Sketch.decode(json['sketch'] as String),
        );
      }
    }
  } catch (_) {
    // Fall through: treat the composite as the picture.
  }
  return MarkupSource(originalPath: path, sketch: null);
}

/// The image at [path] decoded: its size in pixels.
Future<ui.Size> imageSizeOf(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  final size = ui.Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// The image with [sketch] drawn over it, as a PNG at the image's native
/// resolution. Needs the engine (inside `runAsync` in widget tests).
Future<Uint8List> renderMarkedImage(String originalPath, Sketch sketch) async {
  final codec = await ui.instantiateImageCodec(
    await File(originalPath).readAsBytes(),
  );
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawImage(image, Offset.zero, Paint());
  InkPainter(strokes: sketch.strokes).paint(canvas, Size(w, h));
  final picture = recorder.endRecording();
  final out = await picture.toImage(image.width, image.height);
  picture.dispose();
  image.dispose();
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return data!.buffer.asUint8List();
}

/// Saves the marks: writes the composite and sidecar, points [attachment]'s
/// row at the composite and clears `storage_key` so sync uploads it. A
/// sketch with no strokes restores the original instead. Returns the new
/// path.
Future<String> saveImageMarkup(
  AppDatabase db,
  Attachment attachment, {
  required String originalPath,
  required Sketch sketch,
}) async {
  final old = attachment.path;
  final hadSidecar = old != null && await File(markupSidecarPath(old)).exists();
  String newPath;
  if (sketch.strokes.isEmpty) {
    newPath = originalPath;
  } else {
    final png = await renderMarkedImage(originalPath, sketch);
    newPath = await saveBytesToAppStorage(
      png,
      'attachments',
      '${p.basenameWithoutExtension(originalPath)}-marked.png',
    );
    await File(markupSidecarPath(newPath)).writeAsString(
      jsonEncode({'original': originalPath, 'sketch': sketch.encode()}),
    );
  }
  await (db.update(
    db.attachments,
  )..where((t) => t.id.equals(attachment.id))).write(
    AttachmentsCompanion(
      path: Value(newPath),
      storageKey: const Value(null),
      updatedAt: Value(DateTime.now()),
    ),
  );
  if (hadSidecar && old != newPath) {
    for (final f in [old, markupSidecarPath(old)]) {
      try {
        await File(f).delete();
      } catch (_) {}
    }
  }
  return newPath;
}
