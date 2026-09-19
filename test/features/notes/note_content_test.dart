import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_content.dart';

void main() {
  test('encode/decode round-trips a rich document', () {
    final document = Document()..insert(0, 'Hello world');
    document.format(0, 5, Attribute.bold);

    final encoded = encodeNoteContent(document);
    final decoded = decodeNoteContent(encoded);

    expect(decoded.toPlainText().trim(), 'Hello world');
    expect(decoded.toDelta(), document.toDelta());
  });

  test('empty content decodes to an empty document', () {
    expect(decodeNoteContent('').toPlainText().trim(), isEmpty);
  });

  test('legacy plain-text content (pre-rich-text notes) decodes as plain text', () {
    final decoded = decodeNoteContent('just some plain text');
    expect(decoded.toPlainText().trim(), 'just some plain text');
  });

  test('malformed JSON falls back to treating the string as plain text', () {
    final decoded = decodeNoteContent('{not valid json');
    expect(decoded.toPlainText().trim(), '{not valid json');
  });

  test('notePlainTextPreview collapses newlines into a single line', () {
    final document = Document()..insert(0, 'Line one\nLine two');
    final content = encodeNoteContent(document);

    expect(notePlainTextPreview(content), 'Line one Line two');
  });
}
