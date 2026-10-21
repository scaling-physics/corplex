import 'dart:convert';

import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/footnote_embed.dart';
import 'package:corplex/features/notes/footnote_markers.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

List<String> _texts(String s) => [for (final f in findFootnotes(s)) f.text];

void main() {
  group('markers', () {
    test('finds simple, nested and several footnotes', () {
      expect(_texts('A^[one] and B^[two [x] three].'), [
        'one',
        'two [x] three',
      ]);
      expect(_texts('x^[see [@smith2020, p. 4] and \$a^2\$]'), [
        'see [@smith2020, p. 4] and \$a^2\$',
      ]);
    });

    test('offsets cover the whole marker', () {
      final f = findFootnotes('ab^[cd]ef').single;
      expect((f.start, f.end), (2, 7));
    });

    test(
      'reference-style markers, escapes and unbalanced text are not footnotes',
      () {
        expect(_texts('see [^1] and [^note]'), isEmpty);
        expect(_texts(r'a \^[not one]'), isEmpty);
        expect(_texts('open ^[never closed'), isEmpty);
        expect(_texts('spans\n^[no\nnewline]'), isEmpty);
      },
    );

    test('brackets inside inline maths do not count', () {
      expect(_texts('x \$y^[1]\$ and ^[real]'), ['real']);
      expect(_texts('^[range \$[0,1)\$ ok]'), ['range \$[0,1)\$ ok']);
    });

    test('balance escapes unmatched brackets and flattens line breaks', () {
      expect(balanceFootnoteText('plain [@k] ok'), 'plain [@k] ok');
      expect(balanceFootnoteText('a ] b'), r'a \] b');
      expect(balanceFootnoteText('a [ b'), r'a \[ b');
      expect(balanceFootnoteText('x\ny'), 'x y');
      expect(footnoteMarker('a ] b'), r'^[a \] b]');
      // And it parses back to the same text.
      expect(
        footnoteDisplayText(findFootnotes(footnoteMarker('a ] b')).single.text),
        'a ] b',
      );
    });

    test('replaceFootnotes flattens for previews', () {
      expect(
        replaceFootnotes('Hello^[a note] world', (t) => ' $t '),
        'Hello a note  world',
      );
    });
  });

  group('stored <-> editor', () {
    test('plain round trip, formatting kept around the footnote', () {
      final stored = _delta([
        {'insert': 'Hello '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': ' text^[a note] after.\n'},
      ]);
      final editor = jsonDecode(footnotesToEmbeds(stored)) as List;
      expect(editor.any((o) => (o['insert'] as Object) is Map), isTrue);
      final doc = editorDocument(stored);
      // The footnote is one character in the editor.
      expect(doc.toPlainText(), 'Hello bold text￼ after.\n');
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(stored)),
      );
    });

    test('a footnote straddling a formatting change is still one footnote', () {
      final stored = _delta([
        {'insert': 'x^[a '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': ' word] end\n'},
      ]);
      final doc = editorDocument(stored);
      expect(doc.toPlainText(), 'x￼ end\n');
      final data = doc
          .toDelta()
          .toList()
          .map((o) => o.data)
          .whereType<Map>()
          .single[footnoteEmbedType];
      expect(data, 'a bold word');
    });

    test('citations and maths inside a footnote stay raw and round trip', () {
      const text = r'See [@smith2020, p. 4] and $x^2$ for [details]';
      final stored = _delta([
        {'insert': 'Claim^[$text] holds, per [@jones2019] and \$y\$.\n'},
      ]);
      final doc = editorDocument(stored);
      final delta = doc.toDelta();
      final embeds = [
        for (final op in delta.toList())
          if (op.data is Map) (op.data as Map).keys.single,
      ];
      // The outer citation and maths became embeds; the inner ones did not.
      expect(embeds, [footnoteEmbedType, 'cite', 'math']);
      final foot = delta
          .toList()
          .map((o) => o.data)
          .whereType<Map>()
          .firstWhere((m) => m.containsKey(footnoteEmbedType));
      expect(foot[footnoteEmbedType], text);
      expect(
        storedFromEditor(doc),
        encodeNoteContent(decodeNoteContent(stored)),
      );
    });

    test('inline code and code blocks are left alone', () {
      final stored = _delta([
        {'insert': 'type '},
        {
          'insert': 'a^[b]',
          'attributes': {'code': true},
        },
        {'insert': ' now\n'},
        {'insert': 'x^[in block]'},
        {
          'insert': '\n',
          'attributes': {'code-block': 'plain'},
        },
      ]);
      expect(footnotesToEmbeds(stored), stored);
    });

    test('content without footnotes or JSON is untouched', () {
      expect(footnotesToEmbeds('just words ^[x]'), 'just words ^[x]');
      final s = _delta([
        {'insert': 'refs [^1]\n'},
      ]);
      expect(footnotesToEmbeds(s), s);
      expect(footnoteEmbedsToText(s), s);
    });

    test('an embed with brackets in its text is stored escaped', () {
      final editor = _delta([
        {
          'insert': {footnoteEmbedType: 'half ] open'},
        },
        {'insert': '\n'},
      ]);
      final stored = footnoteEmbedsToText(editor);
      expect((jsonDecode(stored) as List).first['insert'], r'^[half \] open]');
      expect(findFootnotes(r'^[half \] open]').single.text, r'half \] open');
    });
  });

  group('previews and word count', () {
    test('a preview reads the footnote as words', () {
      final stored = _delta([
        {'insert': 'Hello^[a note] world\n'},
      ]);
      expect(notePlainTextPreview(stored), 'Hello a note world');
    });

    test('footnote words are counted apart from the body', () {
      final doc = editorDocument(
        _delta([
          {'insert': 'One two three^[four five [@k] six] seven.\n'},
        ]),
      );
      final stats = noteStats(doc);
      expect(stats.words, 4);
      expect(stats.footnoteWords, 3);
      expect(stats.citations, 0);
    });
  });

  group('numbering', () {
    test('footnotes are numbered 1..n in document order, live', () {
      final c = QuillController(
        document: editorDocument(
          _delta([
            {'insert': 'a^[one] b^[two]\nc^[three]\n'},
          ]),
        ),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final scope = FootnoteScope.of(c);
      expect(scope.total, 3);
      expect([for (var i = 0; i < 20; i++) scope.numberAt(i)].nonNulls, [
        1,
        2,
        3,
      ]);
      var told = 0;
      scope.addListener(() => told++);
      // A new footnote at the very start renumbers the rest.
      c.replaceText(
        0,
        0,
        const Embeddable(footnoteEmbedType, 'new'),
        const TextSelection.collapsed(offset: 1),
      );
      expect(scope.total, 4);
      expect(scope.numberAt(0), 1);
      expect(scope.numberAt(2), 2);
      expect(told, greaterThan(0));
      c.dispose();
    });

    test('footnotes in a collapsed section still count', () {
      final folded = jsonEncode([
        {
          'insert': {footnoteEmbedType: 'hidden'},
        },
        {'insert': '\n'},
      ]);
      final c = QuillController(
        document: Document.fromJson([
          {
            'insert': {'fold': folded},
          },
          {'insert': 'x'},
          {
            'insert': {footnoteEmbedType: 'shown'},
          },
          {'insert': '\n'},
        ]),
        selection: const TextSelection.collapsed(offset: 0),
      );
      final scope = FootnoteScope.of(c);
      expect(scope.total, 2);
      expect(scope.numberAt(2), 2);
      c.dispose();
    });
  });

  group('editor', () {
    EditableText.debugDeterministicCursor = true;

    Future<void> pump(WidgetTester tester, QuillController c) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            supportedLocales: FlutterQuillLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    Expanded(
                      child: QuillEditor.basic(
                        controller: c,
                        config: const QuillEditorConfig(
                          embedBuilders: [FootnoteEmbedBuilder()],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => insertFootnote(context, c),
                      child: const Text('footnote'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('the Footnote command inserts one and opens its editor', (
      tester,
    ) async {
      final c = QuillController.basic();
      c.replaceText(0, 0, 'Claim', const TextSelection.collapsed(offset: 5));
      await pump(tester, c);
      await tester.tap(find.text('footnote'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('footnote-text')),
        'Source: [@smith2020]',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), 'Claim￼\n');
      expect(
        (jsonDecode(storedFromEditor(c.document)) as List).first['insert'],
        'Claim^[Source: [@smith2020]]\n',
      );
      // The chip shows its number.
      expect(find.text('1'), findsOneWidget);
      c.dispose();
    });

    testWidgets('cancelling leaves no footnote; tapping edits and removes', (
      tester,
    ) async {
      final c = QuillController.basic();
      await pump(tester, c);
      await tester.tap(find.text('footnote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), '\n');

      c.replaceText(
        0,
        0,
        const Embeddable(footnoteEmbedType, 'old'),
        const TextSelection.collapsed(offset: 1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('footnote-text')),
        'new text',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        (jsonDecode(storedFromEditor(c.document)) as List).first['insert'],
        '^[new text]\n',
      );
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), '\n');
      c.dispose();
    });
  });
}
