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

  test(
    'legacy plain-text content (pre-rich-text notes) decodes as plain text',
    () {
      final decoded = decodeNoteContent('just some plain text');
      expect(decoded.toPlainText().trim(), 'just some plain text');
    },
  );

  test('malformed JSON falls back to treating the string as plain text', () {
    final decoded = decodeNoteContent('{not valid json');
    expect(decoded.toPlainText().trim(), '{not valid json');
  });

  test('notePlainTextPreview collapses newlines into a single line', () {
    final document = Document()..insert(0, 'Line one\nLine two');
    final content = encodeNoteContent(document);

    expect(notePlainTextPreview(content), 'Line one Line two');
  });

  group('appendQuote', () {
    test('adds a block quote with a linked page reference', () {
      final out = appendQuote(
        '',
        quote: 'Attention is all you need.',
        page: 3,
        pageLink: 'corplex://paper/p1?page=3',
      );
      final doc = decodeNoteContent(out);
      expect(doc.toPlainText(), 'Attention is all you need.\n— p. 3\n');
      final ops = doc.toDelta().toList();
      expect(ops.any((op) => op.attributes?['blockquote'] == true), isTrue);
      expect(
        ops.firstWhere((op) => op.data == 'p. 3').attributes?['link'],
        'corplex://paper/p1?page=3',
      );
    });

    test('goes after existing text, followed by the comment', () {
      final out = appendQuote(
        encodeNoteContent(Document()..insert(0, 'My thoughts')),
        quote: 'A quote',
        page: 7,
        pageLink: 'corplex://paper/p1?page=7',
        comment: '  Key claim  ',
      );
      expect(
        decodeNoteContent(out).toPlainText(),
        'My thoughts\nA quote\n— p. 7\nKey claim\n',
      );
      // Only the passage is quoted, not the reference or the comment.
      final quoted = decodeNoteContent(out)
          .toDelta()
          .toList()
          .where((op) => op.attributes?['blockquote'] == true);
      expect(quoted, hasLength(1));
    });
  });
}
