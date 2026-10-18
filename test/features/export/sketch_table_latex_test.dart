import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_actions.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/latex_export.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:corplex/features/ink/ink_model.dart';
import 'package:corplex/features/notes/note_markdown.dart';
import 'package:corplex/features/notes/note_table.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

Sketch _sketch({String? text}) => Sketch(
  aspect: 0.5,
  text: text,
  strokes: const [
    InkStroke(
      tool: InkTool.pen,
      color: Color(0xFF223344),
      width: 0.01,
      points: [InkPoint(0.1, 0.1, 0.5), InkPoint(0.8, 0.3, 0.7)],
    ),
    InkStroke(
      tool: InkTool.highlighter,
      color: Color(0xFFFFEB3B),
      width: 0.04,
      points: [InkPoint(0.2, 0.2, 0.5), InkPoint(0.6, 0.2, 0.5)],
    ),
    InkStroke(
      tool: InkTool.pen,
      color: Color(0xFF000000),
      width: 0.01,
      points: [InkPoint(0.5, 0.4, 0.5)],
    ),
  ],
);

final _table = NoteTable(
  rows: [
    ['Name', 'A | B'],
    ['x_1', '50% & more'],
  ],
);

String _content(List<Map<String, Object?>> ops) => jsonEncode(ops);

String _withEmbeds({String? sketchText}) => _content([
  {'insert': 'Before\n'},
  {
    'insert': {'sketch': _sketch(text: sketchText).encode()},
  },
  {'insert': '\n'},
  {
    'insert': {'table': _table.encode()},
  },
  {'insert': '\nAfter\n'},
]);

Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

String _utf8Part(Archive a, String name) =>
    utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('a'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            year: const Value(2017),
            citekey: const Value('vaswani2017'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('b'),
            title: 'BERT',
            authors: const Value('Devlin, Jacob'),
            year: const Value(2019),
            citekey: const Value('devlin2019'),
          ),
        );
  });
  tearDown(() => db.close());

  Future<ExportDoc> build(String content, {String title = 'Note'}) =>
      buildExportDoc(db, [ExportNote(title, content)], title: title);

  group('model', () {
    test('sketch and table embeds become their own blocks', () async {
      final doc = await build(_withEmbeds());
      expect(doc.blocks.where((b) => b.kind == BlockKind.image), hasLength(1));
      final t = doc.blocks.singleWhere((b) => b.kind == BlockKind.table);
      expect(t.table!.rows[1][0], 'x_1');
      expect(doc.blocks.map((b) => b.text).join(), isNot(contains('[Sketch]')));
    });
  });

  group('markdown', () {
    test('share: sketch is an inline SVG data URI, table a pipe table', () {
      final md = noteToMarkdown(
        title: 'T',
        content: _withEmbeds(sketchText: 'hello [world]'),
      );
      final m = RegExp(
        r'!\[hello world\]\(data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)\)',
      ).firstMatch(md);
      expect(m, isNotNull);
      expect(utf8.decode(base64Decode(m!.group(1)!)), startsWith('<svg'));
      expect(md, contains('| Name | A \\| B |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| x_1 | 50% & more |'));
      // Blank lines keep the table out of the neighbouring paragraphs.
      expect(md, contains('Before\n\n!['));
      expect(md, contains('\n\n| Name'));
    });

    test('a headerless table gets an empty header row', () {
      final t = NoteTable(
        rows: [
          ['a', 'b'],
        ],
        header: false,
      );
      expect(tableMarkdown(t), '|  |  |\n| --- | --- |\n| a | b |');
    });

    test('ExportDoc markdown matches', () async {
      final md = exportToMarkdown(await build(_withEmbeds()));
      expect(md, contains('![Sketch](data:image/svg+xml;base64,'));
      expect(md, contains('| Name | A \\| B |'));
    });
  });

  group('docx', () {
    test('picture parts, relationship, content type and drawing XML', () async {
      final doc = await build(_withEmbeds(sketchText: 'say "hi"'));
      final image = doc.blocks.firstWhere((b) => b.kind == BlockKind.image);
      final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final zip = ZipDecoder().decodeBytes(
        exportToDocx(doc, images: {image: png}),
      );
      expect(zip.findFile('word/media/image1.png')!.content, png);
      final rels = _utf8Part(zip, 'word/_rels/document.xml.rels');
      expect(rels, contains('Id="rId2"'));
      expect(rels, contains('Target="media/image1.png"'));
      expect(rels, contains('relationships/image'));
      expect(
        _utf8Part(zip, '[Content_Types].xml'),
        contains('<Default Extension="png" ContentType="image/png"/>'),
      );
      final xml = _utf8Part(zip, 'word/document.xml');
      expect(xml, contains('<wp:inline'));
      expect(xml, contains('<a:blip r:embed="rId2"/>'));
      expect(xml, contains('descr="say &quot;hi&quot;"'));
      expect(xml, contains('xmlns:pic='));
      // Well-formed enough to parse as XML: tags balance.
      for (final tag in ['w:p', 'w:tbl', 'w:tr', 'w:tc', 'w:drawing']) {
        expect(
          RegExp('<$tag[ >]').allMatches(xml).length,
          RegExp('</$tag>').allMatches(xml).length,
          reason: tag,
        );
      }
    });

    test('table: borders, header row, grid and trailing paragraph', () async {
      final xml = _utf8Part(
        ZipDecoder().decodeBytes(exportToDocx(await build(_withEmbeds()))),
        'word/document.xml',
      );
      expect(xml, contains('<w:tbl>'));
      expect(xml, contains('<w:tblBorders>'));
      expect(xml, contains('<w:tblHeader/>'));
      expect(RegExp('<w:gridCol').allMatches(xml), hasLength(2));
      expect(xml, contains('50% &amp; more'));
      expect(xml, contains('</w:tbl><w:p/>'));
      // Without a picture there is no png part, and the sketch is a line.
      expect(xml, contains('[Sketch]'));
    });

    test('no images means no png default', () async {
      final zip = ZipDecoder().decodeBytes(
        exportToDocx(await build('[{"insert":"x\\n"}]')),
      );
      expect(
        _utf8Part(zip, '[Content_Types].xml'),
        isNot(contains('Extension="png"')),
      );
    });

    testWidgets('exportToDocxWithImages renders a real PNG', (tester) async {
      await tester.runAsync(() async {
        final doc = await build(_withEmbeds());
        final zip = ZipDecoder().decodeBytes(await exportToDocxWithImages(doc));
        final png = zip.findFile('word/media/image1.png')!.content as List;
        expect(png.take(4), [137, 80, 78, 71]);
        expect(_utf8Part(zip, 'word/document.xml'), contains('<wp:extent'));
      });
    });
  });

  group('pdf', () {
    test('a drawing and a table make a valid, larger PDF', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final plain = await exportToPdf(
        await build('[{"insert":"Before\\nAfter\\n"}]'),
        loadFont: _fromDisk,
      );
      final rich = await exportToPdf(
        await build(_withEmbeds()),
        loadFont: _fromDisk,
      );
      expect(String.fromCharCodes(rich.take(5)), '%PDF-');
      expect(
        String.fromCharCodes(rich.skip(rich.length - 10)),
        contains('%%EOF'),
      );
      expect(rich.length, greaterThan(plain.length));
    });
  });

  group('vault', () {
    test('drawings are SVG files in Attachments, linked like images', () async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Lab: day 1'),
              content: Value(_withEmbeds(sketchText: 'x|y')),
            ),
          );
      final result = await buildVaultArchive(db);
      final files = {
        for (final f in result.archive.files)
          if (f.isFile) f.name: utf8.decode(f.content as List<int>),
      };
      const svg = 'Corplex/Attachments/Lab day 1-sketch-1.svg';
      expect(files.keys, contains(svg));
      expect(files[svg], startsWith('<svg'));
      final note = files.entries
          .firstWhere((e) => e.key.startsWith('Corplex/Notes/'))
          .value;
      expect(note, contains('![[Attachments/Lab day 1-sketch-1.svg|x y]]'));
      expect(note, contains('| Name | A \\| B |'));
      expect(note, isNot(contains('[Sketch]')));
    });
  });

  group('latex', () {
    test('escapes specials outside maths and leaves maths alone', () async {
      expect(
        latexEscape(r'50% of $5 & a_b #1 {x} ~ ^ \'),
        r'50\% of \$5 \& a\_b \#1 \{x\} \textasciitilde{} \textasciicircum{} \textbackslash{}',
      );
      final doc = await build(
        _content([
          {'insert': r'Cost is 100% & rising. Let $x_1^2$ hold.'},
          {'insert': '\n'},
          {'insert': r'$$\frac{a}{b}$$'},
          {'insert': '\n'},
        ]),
      );
      final tex = buildLatexProject(doc).main;
      expect(tex, contains(r'Cost is 100\% \& rising. Let $x_1^2$ hold.'));
      expect(tex, contains('\\[\n\\frac{a}{b}\n\\]'));
    });

    test('citations, locators and groups', () async {
      final doc = await build(
        _content([
          {
            'insert':
                'A [@vaswani2017] B [@vaswani2017, p. 42] C [@vaswani2017; '
                '@devlin2019] D [@vaswani2017, pp. 3–5; @devlin2019] E [@?]\n',
          },
        ]),
      );
      final p = buildLatexProject(doc);
      expect(p.main, contains(r'\citep{vaswani2017}'));
      expect(p.main, contains(r'\citep[p.~42]{vaswani2017}'));
      expect(p.main, contains(r'\citep{vaswani2017,devlin2019}'));
      expect(
        p.main,
        contains(
          r'\citetext{\citealp[pp.~3–5]{vaswani2017}; \citealp{devlin2019}}',
        ),
      );
      expect(p.main, contains('[@?]'));
      expect(p.main, contains(r'\bibliography{references}'));
      expect(p.main, contains(r'\usepackage'));
      expect(p.main, isNot(contains('References}')));
      expect(p.bib, contains('@'));
      expect(p.bib, contains('{vaswani2017,'));
      expect(p.bib, contains('{devlin2019,'));
    });

    test(
      'structure: headings, lists, quote, code, styles, highlight',
      () async {
        final doc = await build(
          _content([
            {'insert': 'Intro'},
            {
              'insert': '\n',
              'attributes': {'header': 1},
            },
            {'insert': 'Sub'},
            {
              'insert': '\n',
              'attributes': {'header': 2},
            },
            {
              'insert': 'bold',
              'attributes': {'bold': true},
            },
            {'insert': ' '},
            {
              'insert': 'it',
              'attributes': {'italic': true},
            },
            {'insert': ' '},
            {
              'insert': 'gone',
              'attributes': {'strike': true},
            },
            {'insert': ' '},
            {
              'insert': 'site',
              'attributes': {'link': 'https://e.com/a?b=1#c'},
            },
            {'insert': '\none'},
            {
              'insert': '\n',
              'attributes': {'list': 'bullet'},
            },
            {'insert': 'two'},
            {
              'insert': '\n',
              'attributes': {'list': 'bullet'},
            },
            {'insert': 'q'},
            {
              'insert': '\n',
              'attributes': {'blockquote': true},
            },
            {'insert': 'a = 1'},
            {
              'insert': '\n',
              'attributes': {'code-block': 'plain'},
            },
          ]),
          title: 'My Title_1',
        );
        final tex = buildLatexProject(doc).main;
        expect(tex, contains(r'\documentclass[11pt]{article}'));
        expect(tex, contains(r'\title{My Title\_1}'));
        expect(tex, contains(r'\section{Intro}'));
        expect(tex, contains(r'\subsection{Sub}'));
        expect(tex, contains(r'\textbf{bold}'));
        expect(tex, contains(r'\textit{it}'));
        expect(tex, contains(r'\sout{gone}'));
        expect(tex, contains(r'\href{https://e.com/a?b=1\#c}{site}'));
        expect(
          tex,
          contains('\\begin{itemize}\n\\item one\n\\item two\n\\end'),
        );
        expect(tex, contains('\\begin{quote}\nq\n\\end{quote}'));
        expect(tex, contains('\\begin{verbatim}\na = 1\n\\end{verbatim}'));
        expect(tex, isNot(contains(r'\bibliography{')));
      },
    );

    test('figures, tables, captions and references', () async {
      final doc = await build(
        _content([
          {
            'insert': {'sketch': _sketch(text: 'a loop').encode()},
          },
          {'insert': '\n{#fig:loop} The loop\nAs {@fig:loop} and {@tbl:t1}.\n'},
          {'insert': '{#tbl:t1} Results\n'},
          {
            'insert': {'table': _table.encode()},
          },
          {'insert': '\n'},
        ]),
      );
      final image = doc.blocks.firstWhere((b) => b.kind == BlockKind.image);
      final p = buildLatexProject(
        doc,
        images: {
          image: Uint8List.fromList([1, 2, 3]),
        },
      );
      expect(p.figures.keys, ['figures/sketch-1.png']);
      expect(p.main, contains(r'\begin{figure}[htbp]'));
      expect(p.main, contains(r'\includegraphics'));
      expect(p.main, contains('% Handwriting: a loop'));
      expect(p.main, contains(r'\caption{ The loop}'.replaceAll('{ ', '{')));
      expect(p.main, contains(r'\label{fig:loop}'));
      expect(p.main, contains(r'Figure~\ref{fig:loop}'));
      expect(p.main, contains(r'Table~\ref{tbl:t1}'));
      expect(
        p.main,
        contains(
          '\\begin{table}[htbp]\n\\centering\n\\caption{Results}\n'
          '\\label{tbl:t1}\n\\begin{tabularx}',
        ),
      );
      expect(p.main, contains(r'\textbf{Name} & \textbf{A | B}'));
      expect(p.main, contains(r'x\_1 & 50\% \& more'));
    });

    test('an unrendered drawing falls back to [Sketch]', () async {
      final tex = buildLatexProject(await build(_withEmbeds())).main;
      expect(tex, contains('[Sketch]'));
      expect(tex, isNot(contains('includegraphics')));
    });

    test('project export: report class, chapters and zip file list', () async {
      final doc = await buildExportDoc(db, [
        ExportNote(
          'Chapter One',
          _content([
            {'insert': 'See [@vaswani2017].\n'},
          ]),
        ),
        ExportNote('Chapter Two', _withEmbeds()),
      ], title: 'Thesis');
      final p = buildLatexProject(doc);
      expect(p.main, contains(r'\documentclass[11pt]{report}'));
      expect(p.main, contains(r'\chapter{Chapter One}'));
      expect(p.main, contains(r'\chapter{Chapter Two}'));
      expect(p.main, contains(r'\tableofcontents'));

      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await exportToLatexZip(doc);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((f) => f.name).toSet(), {
        'main.tex',
        'references.bib',
        'figures/sketch-1.png',
      });
      expect(_utf8Part(zip, 'references.bib'), contains('{vaswani2017,'));
    });

    test('the format names a zip', () {
      expect(exportFileName('My Thesis', ExportFormat.latex), 'My Thesis.zip');
      expect(exportFileName('', ExportFormat.latex), 'Corplex export.zip');
    });
  });
}
