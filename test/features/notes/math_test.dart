import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/notes/citation_embed.dart';
import 'package:corplex/features/notes/math_embed.dart';
import 'package:corplex/features/notes/math_markers.dart';
import 'package:corplex/features/notes/math_render.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_markdown.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

List<String> _latex(String s) => [for (final m in findInlineMath(s)) m.latex];

Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('inline maths rules', () {
    test('finds well-formed spans', () {
      expect(_latex(r'Let $x^2$ be $y_i$.'), ['x^2', 'y_i']);
      expect(_latex(r'($a+b$)'), ['a+b']);
      expect(_latex(r'$\frac{a}{b}$'), [r'\frac{a}{b}']);
    });

    test('money is not maths', () {
      expect(_latex(r'It costs $5 and $10 in total'), isEmpty);
      expect(_latex(r'Between $5 and $10.'), isEmpty);
      expect(_latex(r'$5 or $ 10'), isEmpty);
      expect(_latex(r'US$5 and 7$'), isEmpty);
      expect(_latex(r'a $ b $ c'), isEmpty);
    });

    test('escapes, newlines and doubles', () {
      expect(_latex(r'\$x\$'), isEmpty);
      expect(_latex('\$x\ny\$'), isEmpty);
      expect(_latex(r'$$x$$'), isEmpty);
      expect(_latex(r'$a $b$'), ['b']);
      expect(_latex(r'$x$5'), isEmpty);
    });

    test('display line', () {
      expect(displayMathOf(r'$$ \int_0^1 x\,dx $$'), r'\int_0^1 x\,dx');
      expect(displayMathOf(r'$$x$$'), 'x');
      expect(displayMathOf(r'$$$$'), isNull);
      expect(displayMathOf(r'see $$x$$'), isNull);
    });
  });

  group('round trip', () {
    test('inline and display maths survive load and save', () {
      final stored = encodeNoteContent(
        decodeNoteContent(
          _delta([
            {'insert': 'Energy \$E=mc^2\$ here\n\$\$ \\int f \$\$\nAfter\n'},
          ]),
        ),
      );
      final editor = mathToEmbeds(stored);
      final ops = jsonDecode(editor) as List;
      expect(
        ops.any(
          (o) => o['insert'] is Map && o['insert'][mathInlineType] != null,
        ),
        isTrue,
      );
      expect(
        ops.any(
          (o) => o['insert'] is Map && o['insert'][mathBlockType] != null,
        ),
        isTrue,
      );
      // The editor can hold it as a document...
      final doc = decodeNoteContent(editor);
      expect(doc.toPlainText(), isNot(contains(r'$')));
      // ...and saving gives the stored form back exactly.
      expect(
        encodeNoteContent(
          decodeNoteContent(mathEmbedsToText(encodeNoteContent(doc))),
        ),
        stored,
      );
    });

    test('bold maths keeps its attributes; code keeps its dollars', () {
      final editor = mathToEmbeds(
        _delta([
          {
            'insert': r'$x$',
            'attributes': {'bold': true},
          },
          {
            'insert': r'$y$',
            'attributes': {'code': true},
          },
          {'insert': '\n'},
        ]),
      );
      final ops = jsonDecode(editor) as List;
      expect(ops.first['attributes'], {'bold': true});
      expect(ops.first['insert'], {mathInlineType: 'x'});
      expect(ops[1]['insert'], r'$y$');
    });

    test('old plain text without dollars and non-JSON are untouched', () {
      expect(mathToEmbeds('just words'), 'just words');
      expect(mathToEmbeds(r'$5 and $10'), r'$5 and $10');
    });

    test('multi-line LaTeX is folded onto one stored line', () {
      final saved = mathEmbedsToText(
        _delta([
          {
            'insert': {mathBlockType: 'a\n+ b'},
          },
          {'insert': '\n'},
        ]),
      );
      expect(jsonDecode(saved)[0]['insert'], r'$$ a + b $$');
    });
  });

  group('plain-text consumers see LaTeX', () {
    final stored = _delta([
      {'insert': 'Let \$x^2\$ hold\n\$\$ \\frac{a}{b} \$\$\n'},
    ]);

    test('preview', () {
      expect(notePlainTextPreview(stored), contains(r'$x^2$'));
      expect(notePlainTextPreview(stored), contains(r'\frac{a}{b}'));
    });

    test('markdown', () {
      final md = noteToMarkdown(title: 'T', content: stored);
      expect(md, contains(r'Let $x^2$ hold'));
      expect(md, contains(r'$$ \frac{a}{b} $$'));
    });

    test('markdown of an editor-form document still gives the source', () {
      final md = noteToMarkdown(title: '', content: mathToEmbeds(stored));
      expect(md, contains(r'$x^2$'));
    });
  });

  group('export', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.inMemoryForTesting());
    tearDown(() => db.close());

    final content = _delta([
      {
        'insert': 'Costs \$5 and \$10; but \$x^2\$ is maths.\n\$\$ \\sum_i i \$\$\nBad \$\\frac{\$ and \$\\notacommand\$\n',
      },
    ]);

    Future<ExportDoc> build() =>
        buildExportDoc(db, [ExportNote('Maths', content)], title: 'Maths');

    test('model separates inline and display maths', () async {
      final doc = await build();
      expect(doc.blocks.any((b) => b.kind == BlockKind.displayMath), isTrue);
      final inline = doc.blocks.expand((b) => b.runs).where((r) => r.math);
      expect(inline.map((r) => r.text), contains('x^2'));
      expect(inline.map((r) => r.text), isNot(contains('5 and')));
    });

    test('markdown uses dollars', () async {
      final md = exportToMarkdown(await build());
      expect(md, contains(r'$x^2$'));
      expect(md, contains('\$\$\n\\sum_i i\n\$\$'));
      expect(md, contains(r'Costs $5 and $10'));
    });

    test('docx keeps the source in monospace', () async {
      final bytes = exportToDocx(await build());
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
            as List<int>,
      );
      expect(xml, contains('Consolas'));
      expect(xml, contains(r'$x^2$'));
      expect(xml, contains(r'$$ \sum_i i $$'));
      expect('<w:r>'.allMatches(xml).length, '</w:r>'.allMatches(xml).length);
    });

    testWidgets('pdf renders maths and survives invalid LaTeX', (tester) async {
      final doc = await build();
      late List<int> withMaths;
      await tester.runAsync(() async {
        withMaths = await exportToPdf(doc, loadFont: _fromDisk);
        final plain = await exportToPdf(
          ExportDoc('x', [
            const ExportBlock(BlockKind.paragraph, [Run('hello')]),
          ]),
          loadFont: _fromDisk,
        );
        expect(String.fromCharCodes(withMaths.sublist(0, 5)), '%PDF-');
        expect(withMaths.length, greaterThan(plain.length));
      });
    });

    testWidgets('renderMathPng draws valid and rejects invalid', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final ok = await renderMathPng(r'\frac{a}{b}', display: true);
        expect(ok, isNotNull);
        expect(ok!.png.sublist(1, 4), [0x50, 0x4E, 0x47]);
        expect(ok.width, greaterThan(0));
        expect(await renderMathPng(r'\frac{'), isNull);
        expect(await renderMathPng(''), isNull);
      });
    });
  });

  group('editor', () {
    EditableText.debugDeterministicCursor = true;

    Future<QuillController> pump(WidgetTester tester, QuillController c) async {
      await tester.pumpWidget(
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
                        embedBuilders: [
                          MathInlineEmbedBuilder(),
                          MathBlockEmbedBuilder(),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => insertDisplayMath(context, c),
                    child: const Text('equation'),
                  ),
                  TextButton(
                    onPressed: () => convertTypedDollar(
                      context,
                      c,
                      c.selection.baseOffset - 1,
                    ),
                    child: const Text('typed'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return c;
    }

    testWidgets('typing a closing dollar makes a chip; money does not', (
      tester,
    ) async {
      final c = QuillController.basic();
      await pump(tester, c);
      c.replaceText(
        0,
        0,
        r'cost $5 and $10',
        TextSelection.collapsed(offset: 15),
      );
      await tester.tap(find.text('typed'));
      await tester.pump();
      expect(c.document.toPlainText(), isNot(contains('￼')));

      final d = QuillController.basic();
      await pump(tester, d);
      d.replaceText(0, 0, r'let $x^2$', TextSelection.collapsed(offset: 9));
      await tester.tap(find.text('typed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(d.document.toPlainText(), startsWith('let ￼'));
      expect(
        jsonDecode(
          encodeNoteContent(
            decodeNoteContent(mathEmbedsToText(encodeNoteContent(d.document))),
          ),
        )[0]['insert'],
        r'let $x^2$'
        '\n',
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('the Equation command inserts a block and edits it', (
      tester,
    ) async {
      final c = QuillController.basic();
      await pump(tester, c);
      await tester.tap(find.text('equation'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, r'\frac{a}{b}');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final ops = c.document.toDelta().toJson();
      expect(
        ops.any(
          (o) =>
              o['insert'] is Map &&
              o['insert'][mathBlockType] == r'\frac{a}{b}',
        ),
        isTrue,
      );
      expect(
        jsonDecode(
          mathEmbedsToText(encodeNoteContent(c.document)),
        )[0]['insert'],
        r'$$ \frac{a}{b} $$',
      );
    });

    testWidgets('invalid LaTeX is kept and does not crash', (tester) async {
      final c = QuillController.basic();
      await pump(tester, c);
      await tester.tap(find.text('equation'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, r'\frac{');
      await tester.pump();
      expect(find.textContaining('Not valid LaTeX'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        c.document.toDelta().toJson().any((o) => o['insert'] is Map),
        isTrue,
      );
    });

    testWidgets('cancelling the Equation sheet leaves no block', (
      tester,
    ) async {
      final c = QuillController.basic();
      await pump(tester, c);
      await tester.tap(find.text('equation'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        c.document.toDelta().toJson().any((o) => o['insert'] is Map),
        isFalse,
      );
    });
  });

  test('citations and maths coexist in the editor round trip', () {
    final stored = _delta([
      {'insert': 'See [@a2020] and \$x\$\n'},
    ]);
    final editor = citationsToEmbeds(mathToEmbeds(stored));
    final back = citationEmbedsToText(
      mathEmbedsToText(encodeNoteContent(decodeNoteContent(editor))),
    );
    expect(jsonDecode(back)[0]['insert'], 'See [@a2020] and \$x\$\n');
  });
}
