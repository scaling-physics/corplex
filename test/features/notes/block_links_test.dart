import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/block_ids.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/note_sections.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

String _stored(List<Map<String, dynamic>> ops) => jsonEncode(ops);

/// Intro / Methods (with a paragraph carrying ^abc123) / Sub / Results.
final _note = _stored([
  {'insert': 'Intro'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'First para.\nA claim worth citing. ^abc123\n'},
  {'insert': 'Methods'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'We did things.\n'},
  {'insert': 'Sub'},
  {
    'insert': '\n',
    'attributes': {'header': 2},
  },
  {'insert': 'Detail.\n'},
  {'insert': 'Results'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {'insert': 'It worked.\n'},
]);

void main() {
  group('block id markers', () {
    test('a line-final marker is one embed in the editor and back', () {
      final doc = editorDocument(_note);
      final delta = doc.toDelta().toJson();
      expect(
        delta.any(
          (op) =>
              op['insert'] is Map && op['insert'][blockIdEmbedType] == 'abc123',
        ),
        isTrue,
      );
      // The text no longer holds the marker; the embed counts as one char.
      expect(doc.toPlainText(), isNot(contains('^abc123')));
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(_note)),
      );
    });

    test('only a marker at the end of a line counts', () {
      final stored = _stored([
        {'insert': 'a ^mid and more\nb ^end\nplain^nospace\n'},
      ]);
      final delta = editorDocument(stored).toDelta().toJson();
      final ids = [
        for (final op in delta)
          if (op['insert'] is Map) (op['insert'] as Map)[blockIdEmbedType],
      ];
      expect(ids, ['end']);
    });

    test('formatting survives the round trip', () {
      final stored = _stored([
        {'insert': 'bold text'},
        {
          'insert': ' ^zz9',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);
      final doc = editorDocument(stored);
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(stored)),
      );
    });

    test('an embed typed past is moved back to the end of its line', () {
      final doc = editorDocument(
        _stored([
          {'insert': 'claim ^q1w2e3\n'},
        ]),
      );
      // Typing at the end of the line puts text after the embed.
      doc.insert(doc.length - 1, ' more');
      final back = storedFromEditor(doc);
      expect(jsonDecode(back), [
        {'insert': 'claim more ^q1w2e3\n'},
      ]);
    });

    test('withoutBlockIds removes markers in either form', () {
      final text = decodeNoteContent(_note).toDelta();
      final bare = withoutBlockIds(text);
      expect(Document.fromDelta(bare).toPlainText(), isNot(contains('^abc')));
      expect(
        Document.fromDelta(bare).toPlainText(),
        contains('A claim worth citing.\n'),
      );
      final fromEditor = withoutBlockIds(editorDocument(_note).toDelta());
      expect(fromEditor, bare);
    });

    test('lists previews without the marker', () {
      expect(notePlainTextPreview(_note), isNot(contains('^abc123')));
    });
  });

  group('resolving heading and block links', () {
    test('a heading is matched case-insensitively, first match wins', () {
      final lines = docLines(editorDocument(_note).toDelta());
      final sel = selectionForTarget(
        lines,
        const NoteLinkTarget('n', heading: '  methods '),
      )!;
      final text = editorDocument(_note).toPlainText();
      expect(text.substring(sel.start, sel.end), 'Methods');
    });

    test('a block selects its paragraph in the editor document', () {
      final doc = editorDocument(_note);
      final lines = docLines(doc.toDelta());
      final sel = selectionForTarget(
        lines,
        const NoteLinkTarget('n', block: 'abc123'),
      )!;
      // The embed is the line's last character.
      expect(
        doc.toPlainText().substring(sel.start, sel.end),
        'A claim worth citing.￼',
      );
      expect(
        selectionInContent(_note, const NoteLinkTarget('n', block: 'abc123')),
        sel,
      );
    });

    test('unknown headings and blocks resolve to nothing', () {
      expect(
        selectionInContent(_note, const NoteLinkTarget('n', heading: 'Nope')),
        isNull,
      );
      expect(
        selectionInContent(_note, const NoteLinkTarget('n', block: 'zzzzzz')),
        isNull,
      );
    });

    test('a heading section runs to the next heading of the same level', () {
      final methods = sectionOf(
        editorDocument(_note).toDelta(),
        const NoteLinkTarget('n', heading: 'Methods'),
      )!;
      final text = Document.fromDelta(methods).toPlainText();
      expect(text, contains('We did things.'));
      expect(text, contains('Detail.'));
      expect(text, isNot(contains('It worked.')));
      final sub = sectionOf(
        editorDocument(_note).toDelta(),
        const NoteLinkTarget('n', heading: 'Sub'),
      )!;
      expect(Document.fromDelta(sub).toPlainText(), 'Sub\nDetail.\n');
    });

    test('a block section is one paragraph without its marker', () {
      final block = sectionOf(
        decodeNoteContent(_note).toDelta(),
        const NoteLinkTarget('n', block: 'abc123'),
      )!;
      expect(
        Document.fromDelta(block).toPlainText(),
        'A claim worth citing.\n',
      );
      expect(
        sectionOf(
          decodeNoteContent(_note).toDelta(),
          const NoteLinkTarget('n', block: 'nope'),
        ),
        isNull,
      );
    });

    test('headingsOf lists headings with levels', () {
      final headings = headingsOf(docLines(editorDocument(_note).toDelta()));
      expect(
        [for (final h in headings) (h.text, h.level)],
        [('Intro', 1), ('Methods', 1), ('Sub', 2), ('Results', 1)],
      );
    });
  });

  group('assigning block ids', () {
    test('in a live document: one embed, reused on a second ask', () {
      final doc = editorDocument(_note);
      final lines = docLines(doc.toDelta());
      final first = lines.firstWhere((l) => l.text == 'First para.');
      final id = assignBlockIdIn(doc, first.start);
      expect(id, matches(RegExp(r'^[a-z0-9]{6}$')));
      expect(assignBlockIdIn(doc, first.start), id);
      expect(storedFromEditor(doc), contains('First para. ^$id\\n'));
      // The line that had one keeps it.
      final claim = docLines(doc.toDelta())
          .firstWhere((l) => l.blockId == 'abc123');
      expect(assignBlockIdIn(doc, claim.start), 'abc123');
    });

    test('in another note: written to its stored content', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('t'),
              title: const Value('Target'),
              content: Value(_note),
            ),
          );
      final start = docLines(editorDocument(_note).toDelta())
          .firstWhere((l) => l.text == 'It worked.')
          .start;
      final id = await assignBlockIdInNote(db, 't', start);
      expect(id, isNotNull);
      final row = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('t'))).getSingle();
      expect(
        Document.fromDelta(decodeNoteContent(row.content).toDelta())
            .toPlainText(),
        contains('It worked. ^$id\n'),
      );
      // Doing it again reuses the id and leaves the content alone.
      expect(await assignBlockIdInNote(db, 't', start), id);
      final again = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('t'))).getSingle();
      expect(again.content, row.content);
    });

    test('a locked note is left alone without its key', () async {
      final db = AppDatabase.inMemoryForTesting();
      addTearDown(db.close);
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('l'),
              content: const Value('corplex-locked:v1:k:AAAA'),
            ),
          );
      expect(await assignBlockIdInNote(db, 'l', 0), isNull);
      expect(await assignBlockIdInNote(db, 'missing', 0), isNull);
    });
  });
}
