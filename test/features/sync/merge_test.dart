import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/sync/merge.dart';

/// A note body with one paragraph per entry.
String _note(List<String> paragraphs) => jsonEncode([
  for (final p in paragraphs) {'insert': '$p\n'},
]);

List<String> _paragraphs(String content) {
  final text = decodeNoteContent(content).toPlainText();
  return text.substring(0, text.length - 1).split('\n');
}

void main() {
  group('merge3', () {
    test('edits to different lines both land', () {
      expect(
        merge3(['a', 'b', 'c', 'd'], ['a', 'B', 'c', 'd'], [
          'a',
          'b',
          'c',
          'D',
        ]),
        ['a', 'B', 'c', 'D'],
      );
    });

    test('edits to neighbouring lines are independent', () {
      expect(merge3(['a', 'b', 'c'], ['a', 'B', 'c'], ['a', 'b', 'C']), [
        'a',
        'B',
        'C',
      ]);
    });

    test('both appending keeps both, this device first', () {
      expect(merge3(['a'], ['a', 'mine'], ['a', 'theirs']), [
        'a',
        'mine',
        'theirs',
      ]);
    });

    test('the same change on both sides appears once', () {
      expect(merge3(['a', 'b'], ['a', 'X'], ['a', 'X']), ['a', 'X']);
    });

    test('a line changed differently on both sides keeps both versions', () {
      expect(
        merge3(['a', 'b', 'c'], ['a', 'mine', 'c'], ['a', 'theirs', 'c']),
        ['a', 'mine', 'theirs', 'c'],
      );
    });

    test('a deletion on one side and an insertion elsewhere', () {
      expect(
        merge3(['a', 'b', 'c', 'd'], ['a', 'c', 'd'], [
          'a',
          'b',
          'c',
          'd',
          'e',
        ]),
        ['a', 'c', 'd', 'e'],
      );
    });

    test('deleted here but edited there: the edit survives', () {
      expect(merge3(['a', 'b', 'c'], ['a', 'c'], ['a', 'B', 'c']), [
        'a',
        'B',
        'c',
      ]);
    });

    test('only one side changed', () {
      expect(merge3(['a', 'b'], ['a', 'b'], ['x', 'a', 'b']), ['x', 'a', 'b']);
      expect(merge3(['a', 'b'], ['a'], ['a', 'b']), ['a']);
    });
  });

  group('mergeNoteContent', () {
    test('paragraphs edited on two devices are both kept', () {
      final base = _note(['Intro', 'Method', 'Findings']);
      final phone = _note(['Intro, revised', 'Method', 'Findings']);
      final ipad = _note(['Intro', 'Method', 'Findings', 'Critique']);
      final merged = mergeNoteContent(base, phone, ipad)!;
      expect(_paragraphs(merged), [
        'Intro, revised',
        'Method',
        'Findings',
        'Critique',
      ]);
    });

    test('keeps formatting and loads as a Quill document', () {
      final base = jsonEncode([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'body\n'},
      ]);
      final local = jsonEncode([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'body '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
      final remote = jsonEncode([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'body\nquote'},
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]);
      final merged = mergeNoteContent(base, local, remote)!;
      final doc = Document.fromJson(jsonDecode(merged) as List);
      expect(doc.toPlainText(), 'Title\nbody bold\nquote\n');
      final ops = doc.toDelta().toJson();
      expect(
        ops,
        anyElement(
          equals({
            'insert': 'bold',
            'attributes': {'bold': true},
          }),
        ),
      );
      expect(
        ops.where((o) => (o['attributes'] as Map?)?['header'] == 2),
        hasLength(1),
      );
      expect(
        ops.where((o) => (o['attributes'] as Map?)?['blockquote'] == true),
        hasLength(1),
      );
    });

    test('a sketch embed survives an edit elsewhere', () {
      final sketch = {
        'insert': {'custom': '{"sketch":"{}"}'},
      };
      final base = jsonEncode([
        {'insert': 'a\n'},
        sketch,
        {'insert': '\nb\n'},
      ]);
      final local = jsonEncode([
        {'insert': 'A\n'},
        sketch,
        {'insert': '\nb\n'},
      ]);
      final remote = jsonEncode([
        {'insert': 'a\n'},
        sketch,
        {'insert': '\nb, too\n'},
      ]);
      final merged = jsonDecode(mergeNoteContent(base, local, remote)!) as List;
      expect(merged, [
        {'insert': 'A\n'},
        sketch,
        {'insert': '\nb, too\n'},
      ]);
    });

    test('plain-text (pre-rich-text) bodies are left to last-write-wins', () {
      expect(mergeNoteContent('old', _note(['x']), _note(['y'])), isNull);
    });
  });

  group('mergeRow', () {
    const columns = ['id', 'title', 'content', 'created_at', 'updated_at'];
    Map<String, Object?> row(String title, String content, int at) => {
      'id': 'n1',
      'title': title,
      'content': content,
      'created_at': 1,
      'updated_at': at,
    };

    test('each field takes the side that changed it', () {
      final merged = mergeRow(
        table: 'notes',
        columns: columns,
        base: row('Draft', _note(['a']), 10),
        local: row('Draft', _note(['a', 'mine']), 20),
        remote: row('Final title', _note(['a']), 30),
      );
      expect(merged['title'], 'Final title');
      expect(_paragraphs(merged['content']! as String), ['a', 'mine']);
    });

    test('a title changed on both sides keeps the later one', () {
      final base = row('Draft', _note(['a']), 10);
      expect(
        mergeRow(
          table: 'notes',
          columns: columns,
          base: base,
          local: row('Mine', _note(['a']), 20),
          remote: row('Theirs', _note(['a']), 30),
        )['title'],
        'Theirs',
      );
      expect(
        mergeRow(
          table: 'notes',
          columns: columns,
          base: base,
          local: row('Mine', _note(['a']), 40),
          remote: row('Theirs', _note(['a']), 30),
        )['title'],
        'Mine',
      );
    });
  });
}
