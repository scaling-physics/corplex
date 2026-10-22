import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/ink/free_ink.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/notes/note_content.dart';

const _stroke = InkStroke(
  tool: InkTool.pen,
  color: Color(0xFF2B2F2B),
  width: 0.007,
  points: [InkPoint(0.1, -0.02, 0.5), InkPoint(0.5, 0.3, 0.5)],
);

void main() {
  test('free ink round-trips and reports how low it reaches', () {
    final ink = FreeInk([_stroke]);
    final back = FreeInk.decode(ink.encode());
    expect(back.strokes.single.points, hasLength(2));
    expect(back.bottom, closeTo(0.3 + 0.0035, 1e-9));
    expect(FreeInk.decode('not json').isEmpty, isTrue);
  });

  test('markers are found with the start of their line', () {
    final data = FreeInk([_stroke]).encode();
    final doc = Document.fromJson([
      {'insert': 'One\n'},
      {
        'insert': {freeInkEmbedType: data},
      },
      {'insert': 'Two\nThree\n'},
    ]);
    final found = freeInkIn(doc).single;
    expect(found.offset, 4);
    expect(found.lineStart, 4);
    expect(found.ink.strokes, hasLength(1));
  });

  test('ink never goes into a line holding a drawing or table', () {
    final doc = Document.fromJson([
      {'insert': 'Text\n'},
      {
        'insert': {'sketch': '{"v":1,"a":0.6,"s":[]}'},
      },
      {'insert': '\nAfter\n'},
    ]);
    // Offset 5 is the drawing: the text line before it takes the ink.
    expect(freeInkLine(doc, 5)!.documentOffset, 0);
    expect(freeInkLine(doc, 7)!.toPlainText(), 'After\n');
  });

  test('stored notes keep the marker; previews and search ignore it', () {
    final data = FreeInk([_stroke]).encode();
    const ops = '[{"insert":';
    final stored =
        '$ops{"$freeInkEmbedType":${_quoted(data)}}},{"insert":"Hello\\n"}]';
    final doc = decodeNoteContent(stored);
    expect(freeInkIn(doc), hasLength(1));
    expect(notePlainTextPreview(stored), 'Hello');
  });
}

String _quoted(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
