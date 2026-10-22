import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ink_model.dart';

/// Quill embed type for free ink: pen marks written straight onto a note —
/// over the text, in the margins, between paragraphs — rather than into a
/// drawing. Each line that carries ink holds one of these (invisible, one
/// character, at the start of the line) whose data is that line's strokes.
/// Because the marker is part of the text, the ink moves with its paragraph
/// through edits, undo, sync and merges, with no positions to keep up to date.
const freeInkEmbedType = 'ink';

/// The strokes anchored to one line. Coordinates are in canvas-width units
/// of the note's writing area (x from its left edge, 0..1 across) and y from
/// the top of the line, on the same scale — so the ink keeps its shape and
/// its place beside the paragraph at any window width.
class FreeInk {
  const FreeInk([this.strokes = const []]);

  factory FreeInk.decode(String data) {
    try {
      final json = jsonDecode(data) as Map<String, Object?>;
      return FreeInk([
        for (final s in (json['s'] as List? ?? const []))
          InkStroke.fromJson((s as Map).cast<String, Object?>()),
      ]);
    } catch (_) {
      // Damaged ink shouldn't break the whole note.
      return const FreeInk();
    }
  }

  final List<InkStroke> strokes;

  bool get isEmpty => strokes.isEmpty;

  /// Lowest point reached (canvas-width units below the line's top).
  double get bottom => strokes.fold(0, (m, s) => math.max(m, s.bounds.bottom));

  String encode() => jsonEncode({
    'v': 1,
    's': [for (final s in strokes) s.toJson()],
  });
}

/// One line's free ink in a document: the marker's offset, where its line
/// starts, and what it holds.
typedef PlacedFreeInk = ({int offset, int lineStart, FreeInk ink});

/// Every free-ink marker in [doc], in order.
List<PlacedFreeInk> freeInkIn(Document doc) {
  final out = <PlacedFreeInk>[];
  var offset = 0;
  var lineStart = 0;
  for (final op in doc.toDelta().toList()) {
    final data = op.data;
    if (data is String) {
      final lastBreak = data.lastIndexOf('\n');
      if (lastBreak >= 0) lineStart = offset + lastBreak + 1;
      offset += data.length;
      continue;
    }
    if (data case {freeInkEmbedType: final String raw}) {
      out.add((offset: offset, lineStart: lineStart, ink: FreeInk.decode(raw)));
    }
    offset += 1;
  }
  return out;
}

/// The lines of [doc] in order, inside lists, quotes and code blocks too.
List<Line> _lines(Document doc) => [
  for (final node in doc.root.children)
    if (node is Line)
      node
    else if (node is Block)
      for (final inner in node.children)
        if (inner is Line) inner,
];

/// A line holding nothing but one embed (a drawing, table, display maths,
/// …): free ink can't go in it, since such an embed must stay alone.
bool _embedOnly(Line line) =>
    line.children.length == 1 &&
    line.children.single is Embed &&
    (line.children.single as Embed).value.type != freeInkEmbedType;

/// The line free ink started at [offset] belongs to: the line there, or —
/// when that line is a drawing, table or other embed of its own — the
/// nearest text line before it (else after it). Null if there is none.
Line? freeInkLine(Document doc, int offset) {
  final lines = _lines(doc);
  if (lines.isEmpty) return null;
  final at = offset.clamp(0, doc.length - 1);
  var index = lines.indexWhere(
    (l) => at >= l.documentOffset && at < l.documentOffset + l.length,
  );
  if (index < 0) index = lines.length - 1;
  if (!_embedOnly(lines[index])) return lines[index];
  for (var i = index - 1; i >= 0; i--) {
    if (!_embedOnly(lines[i])) return lines[i];
  }
  for (var i = index + 1; i < lines.length; i++) {
    if (!_embedOnly(lines[i])) return lines[i];
  }
  return null;
}

/// The free-ink marker already in [line], if it has one.
({int offset, FreeInk ink})? freeInkOn(Line line) {
  for (final child in line.children) {
    if (child is Embed && child.value.type == freeInkEmbedType) {
      return (
        offset: child.documentOffset,
        ink: FreeInk.decode(child.value.data as String),
      );
    }
  }
  return null;
}

/// The marker itself draws nothing: the note's [InkCatcher] paints all free
/// ink in one layer above the text.
class FreeInkEmbedBuilder extends EmbedBuilder {
  const FreeInkEmbedBuilder();

  @override
  String get key => freeInkEmbedType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const SizedBox.shrink();
}
