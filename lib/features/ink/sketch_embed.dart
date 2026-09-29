import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ink_model.dart';
import 'ink_painter.dart';
import 'sketch_editor_screen.dart';

/// Quill embed type for a drawing inside a note. The embed's data is the
/// encoded [Sketch], so drawings live in the note's content and sync, copy
/// and version with the text around them.
const sketchEmbedType = 'sketch';

/// `const Sketch().encode()`, as a compile-time constant (checked by a test).
@visibleForTesting
const emptySketchData = '{"v":1,"a":0.6,"s":[]}';

/// Inserts an empty sketch at the cursor (or the end) and opens it for
/// drawing straight away. An untouched sketch is removed again, so
/// tapping "Draw" by mistake leaves no trace.
Future<void> insertSketch(
  BuildContext context,
  QuillController controller,
) async {
  final doc = controller.document;
  final cursor = controller.selection.baseOffset;
  final index = cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor;
  controller.replaceText(
    index,
    0,
    // Inserted directly: BlockEmbed.custom(...) would wrap it in a generic
    // "custom" type that SketchEmbedBuilder's key never matches.
    const CustomBlockEmbed(sketchEmbedType, emptySketchData),
    TextSelection.collapsed(offset: index + 1),
  );
  // Mid-line, Quill first splits the line, so the embed can land one
  // position later than asked.
  final at = _sketchOffsetNear(controller.document, index);
  if (at == null) return;
  await _edit(context, controller, at, const Sketch());
}

/// The offset of a sketch embed at or right after [offset], if any.
int? _sketchOffsetNear(Document doc, int offset) {
  for (final candidate in [offset, offset + 1]) {
    if (candidate >= doc.length) break;
    final leaf = doc.querySegmentLeafNode(candidate).leaf;
    if (leaf is Embed &&
        leaf.value.type == sketchEmbedType &&
        leaf.documentOffset == candidate) {
      return candidate;
    }
  }
  return null;
}

Future<void> _edit(
  BuildContext context,
  QuillController controller,
  int offset,
  Sketch sketch,
) async {
  final edited = await Navigator.of(context).push<Sketch>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SketchEditorScreen(initial: sketch),
    ),
  );
  if (edited == null) return;
  // The embed may have moved if the document changed meanwhile (e.g. sync);
  // only replace it if it's still a sketch at that spot.
  if (_sketchOffsetNear(controller.document, offset) != offset) return;
  if (edited.isEmpty) {
    controller.replaceText(
      offset,
      1,
      '',
      TextSelection.collapsed(offset: offset),
    );
  } else {
    controller.replaceText(
      offset,
      1,
      CustomBlockEmbed(sketchEmbedType, edited.encode()),
      null,
    );
  }
}

/// Renders a sketch block in the note: the drawing on its paper, full
/// width. Tap to draw on it.
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
    final sketch = Sketch.decode(embedContext.node.value.data as String);
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        button: !embedContext.readOnly,
        label: 'Sketch',
        child: GestureDetector(
          onTap: embedContext.readOnly
              ? null
              : () => _edit(
                  context,
                  embedContext.controller,
                  embedContext.node.documentOffset,
                  sketch,
                ),
          child: Container(
            decoration: BoxDecoration(
              color: sketchPaperColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 1 / sketch.aspect,
              child: sketch.isEmpty
                  ? Center(
                      child: Text(
                        'Tap to draw',
                        style: TextStyle(color: c.outline),
                      ),
                    )
                  : CustomPaint(painter: InkPainter(strokes: sketch.strokes)),
            ),
          ),
        ),
      ),
    );
  }
}
