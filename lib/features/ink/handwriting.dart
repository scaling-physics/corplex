import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ocr/ocr_engine.dart';
import 'ink_model.dart';
import 'ink_session.dart' show sketchEmbedType;
import 'sketch_render.dart';

/// The engine that reads handwriting in drawings. Inert (null: no
/// recognition) by default, like every platform seam — `main()` installs
/// the on-device OCR (Apple Vision handles handwriting; ML Kit's Latin
/// model less well). Tests that want recognition override it with a fake.
final inkOcrEngineProvider = Provider<OcrEngine?>((ref) => null);

/// Renders a drawing for recognition: black ink on white, 1600 px wide.
typedef SketchRenderer = Future<Uint8List> Function(Sketch sketch);

Future<Uint8List> renderForRecognition(Sketch sketch) =>
    renderSketchPng(sketch, width: 1600, background: const Color(0xFFFFFFFF));

/// The text [engine] reads in [sketch], lines joined by newlines (empty if
/// none).
Future<String> recognizeHandwriting(
  OcrEngine engine,
  Sketch sketch, {
  SketchRenderer render = renderForRecognition,
}) async {
  final page = await engine.recognize(await render(sketch));
  return page.lines
      .map((l) => l.text.trim())
      .where((t) => t.isNotEmpty)
      .join('\n');
}

/// Identifies a drawing by its strokes alone (not its height or text), so a
/// recognition result is only kept if the strokes are still the ones read.
String strokesKey(Sketch sketch) => Sketch(strokes: sketch.strokes).encode();

/// Every drawing in [doc], with its document offset.
List<({int offset, Sketch sketch})> drawingsIn(Document doc) {
  final out = <({int offset, Sketch sketch})>[];
  var offset = 0;
  for (final op in doc.toDelta().toList()) {
    final data = op.data;
    if (data is Map && data[sketchEmbedType] is String) {
      out.add((
        offset: offset,
        sketch: Sketch.decode(data[sketchEmbedType] as String),
      ));
    }
    offset += op.length ?? 1;
  }
  return out;
}
