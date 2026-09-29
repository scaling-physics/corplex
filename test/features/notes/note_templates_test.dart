import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_templates.dart';

void main() {
  test('the template adds four headed sections and places the cursor', () {
    final c = QuillController.basic();
    addTearDown(c.dispose);
    c.replaceText(0, 0, 'Existing text', null);

    final cursor = insertLiteratureTemplate(c, 13);

    final text = c.document.toPlainText();
    for (final s in literatureNoteSections) {
      expect(text, contains('$s\n'));
    }
    expect(text.startsWith('Existing text\nSummary\n'), isTrue);
    expect(cursor, 'Existing text\nSummary\n'.length);
    final headers = c.document.toDelta().toList().where(
      (op) => op.attributes?['header'] == 2,
    );
    expect(headers, hasLength(4));
    expect(c.selection.baseOffset, cursor);
  });
}
