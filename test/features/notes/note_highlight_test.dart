import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_highlight.dart';

void main() {
  test('palette hexes are valid and stored as the background attribute', () {
    expect(NoteHighlight.values, hasLength(5));
    for (final h in NoteHighlight.values) {
      expect(highlightHex(h.hex), h.hex.substring(1));
      expect(h.attribute.key, 'background');
    }
    expect(highlightHex('red'), isNull);
    expect(highlightHex(null), isNull);
  });

  test('applyHighlight sets, switches and clears a highlight', () {
    final c = QuillController.basic();
    c.replaceText(0, 0, 'hello', const TextSelection.collapsed(offset: 5));
    c.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      ChangeSource.local,
    );
    applyHighlight(c, NoteHighlight.green);
    expect(selectionHighlight(c), NoteHighlight.green.hex);
    applyHighlight(c, NoteHighlight.pink);
    expect(selectionHighlight(c), NoteHighlight.pink.hex);
    applyHighlight(c, NoteHighlight.pink);
    expect(selectionHighlight(c), isNull);
    c.dispose();
  });
}
