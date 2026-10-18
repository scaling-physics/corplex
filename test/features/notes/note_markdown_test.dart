import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/note_markdown.dart';

String _content(List<Map<String, Object?>> ops) => jsonEncode(ops);

void main() {
  test('headings, emphasis, lists, quotes and external links', () {
    final md = noteToMarkdown(
      title: 'Reading notes',
      content: _content([
        {'insert': 'Key ideas'},
        {
          'insert': '\n',
          'attributes': {'header': 1},
        },
        {
          'insert': 'Attention',
          'attributes': {'bold': true},
        },
        {'insert': ' is '},
        {
          'insert': 'all',
          'attributes': {'italic': true},
        },
        {'insert': ' you need, see '},
        {
          'insert': 'arXiv',
          'attributes': {'link': 'https://arxiv.org/abs/1706.03762'},
        },
        {'insert': '\n'},
        {'insert': 'first'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'second'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'point'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': 'A quote'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]),
    );
    expect(md, '''# Reading notes

## Key ideas
**Attention** is *all* you need, see [arXiv](https://arxiv.org/abs/1706.03762)
1. first
2. second
- point
> A quote
''');
  });

  test(
    'app-internal links become plain text; sketches an inline SVG image',
    () {
      final md = noteToMarkdown(
        title: '',
        content: _content([
          {'insert': 'See '},
          {
            'insert': 'Other note',
            'attributes': {'link': noteLink('n2')},
          },
          {'insert': ', '},
          {
            'insert': 'p. 3',
            'attributes': {'link': 'corplex://paper/p1?page=3'},
          },
          {'insert': ' and '},
          {
            'insert': '▸ 1:02',
            'attributes': {'link': 'corplex://audio/a1?t=62'},
          },
          {'insert': '\n'},
          {
            'insert': {'sketch': '{}'},
          },
          {'insert': '\n'},
        ]),
      );
      expect(
        md,
        startsWith(
          'See Other note, p. 3 and ▸ 1:02\n\n![Sketch](data:image/svg+xml;base64,',
        ),
      );
    },
  );

  test('note links round-trip', () {
    expect(parseNoteLink(noteLink('abc')), 'abc');
    expect(parseNoteLink('corplex://paper/abc?page=1'), isNull);
  });
}
