import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/export_actions.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/notes/figure_markers.dart';
import 'package:corplex/features/notes/math_markers.dart';
import 'package:corplex/features/notes/note_markdown.dart';
import 'package:corplex/features/projects/figures.dart';
import 'package:corplex/features/projects/todos.dart';

String body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  group('markers', () {
    test('definitions need a line start, references do not', () {
      final ms = findFigureMarkers('{#fig:a1} Cap {@tbl:b-2} and {#fig:no}');
      expect(ms.map((m) => (m.kind, m.label, m.isDefinition)), [
        (FigureKind.figure, 'a1', true),
        (FigureKind.table, 'b-2', false),
      ]);
      expect(
        findFigureMarkers('x\n{#tbl:t_1} Cap').single.isDefinition,
        isTrue,
      );
      expect(findFigureMarkers('{#fig:a}', lineStart: false), isEmpty);
    });

    test('other syntaxes are left alone', () {
      expect(findFigureMarkers('[@key] [fig: x] [FIG] \$x\$ {@fig:}'), isEmpty);
      expect(findInlineMath(r'{#fig:a} costs $5 and $10'), isEmpty);
    });

    test('round trip is exact', () {
      final stored = jsonEncode([
        {'insert': '{#fig:k3x9q} Place fields in '},
        {
          'insert': 'CA1',
          'attributes': {'bold': true},
        },
        {'insert': ' (see {@tbl:z}) and \$x\$ [@a].\nPlain {#fig:no} text\n'},
      ]);
      final doc = editorDocument(stored);
      final embeds = doc
          .toDelta()
          .toJson()
          .where((o) => o['insert'] is Map)
          .map((o) => (o['insert'] as Map).keys.single)
          .toList();
      expect(embeds, containsAll([figureDefType, figureRefType, 'math']));
      expect(embeds.where((e) => e == figureDefType), hasLength(1));
      expect(storedFromEditor(doc), encodeStored(stored));
    });

    test('definitions: offsets and captions from the editor document', () {
      final doc = editorDocument(
        body('Intro [@a] here\n{#fig:aa} First {@tbl:t}\n{#tbl:t} Second'),
      );
      final defs = figureDefsIn(doc.toDelta());
      expect(defs.map((d) => d.label), ['aa', 't']);
      expect(defs[0].caption, 'First {@tbl:t}');
      expect(doc.toPlainText()[defs[0].offset], '￼');
    });
  });

  group('to-dos', () {
    test('a to-do after figure chips still selects correctly', () {
      final stored = body('{#fig:aa} See {@fig:aa} and \$x\$ then TODO: fix');
      final todo = findTodos(stored).single;
      final shown = editorDocument(stored).toPlainText();
      expect(shown.substring(todo.offset, todo.offset + todo.length), 'TODO:');
    });
  });

  group('markdown share', () {
    test('definitions and references resolve to plain numbers', () {
      final md = noteToMarkdown(
        title: 'T',
        content: jsonEncode([
          {
            'insert':
                '{#fig:a} One\n{#tbl:t} Tab\n{#fig:b} Two, see {@fig:a}, '
                '{@tbl:t} and {@fig:zz}.\n',
          },
        ]),
      );
      expect(md, contains('**Figure 1.** One'));
      expect(md, contains('**Table 1.** Tab'));
      expect(md, contains('**Figure 2.** Two, see Figure 1, Table 1'));
      expect(md, contains('Figure ??.'));
    });

    test('editor-form content works too', () {
      final md = noteToMarkdown(
        title: '',
        content: encodeStored(body('{#fig:a} One {@fig:a}')),
      );
      expect(md.trim(), '**Figure 1.** One Figure 1');
      final viaEditor = noteToMarkdown(
        title: '',
        content: encodeNoteContent2(editorDocument(body('{#fig:a} One'))),
      );
      expect(viaEditor.trim(), '**Figure 1.** One');
    });
  });

  group('export', () {
    late AppDatabase db;
    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
    });
    tearDown(() => db.close());

    final ch1 = ExportNote(
      'Intro',
      jsonEncode([
        {'insert': '{#fig:a} Place fields.\nSee {@fig:b} and {@fig:a}.\n'},
      ]),
    );
    final ch2 = ExportNote(
      'Methods',
      jsonEncode([
        {'insert': '{#tbl:t} Animals.\n{#fig:b} Setup, cf. {@tbl:t}.\n'},
      ]),
    );

    test('a single note uses plain numbers and no front matter', () async {
      final doc = await buildExportDoc(db, [ch1], title: 'x');
      expect(doc.blocks.first.kind, BlockKind.caption);
      expect(doc.blocks.first.text, 'Figure 1. Place fields.');
      expect(doc.blocks.first.runs.first.bold, isTrue);
      expect(doc.blocks[1].text, 'See Figure ?? and Figure 1.');
      expect(doc.blocks.where((b) => b.text == 'List of figures'), isEmpty);
    });

    test('given project numbering, a single note matches the editor', () async {
      final index = buildFigureIndex([
        FigureNote(noteId: 'a', title: 'A', content: ch1.content, chapter: '1'),
        FigureNote(noteId: 'b', title: 'B', content: ch2.content, chapter: '2'),
      ]);
      final doc = await buildExportDoc(db, [ch2], title: 'x', figures: index);
      expect(doc.blocks.first.text, 'Table 2.1. Animals.');
      expect(doc.blocks[1].text, 'Figure 2.1. Setup, cf. Table 2.1.');
      final other = await buildExportDoc(db, [ch1], title: 'x', figures: index);
      expect(other.blocks[1].text, 'See Figure 2.1 and Figure 1.1.');
    });

    for (final csl in [false, true]) {
      test('project export, ${csl ? 'CSL' : 'hand-written'} path', () async {
        final style = csl ? CitationStyle.ieee : CitationStyle.apa;
        final doc = await buildStyledExportDoc(
          db,
          [ch1, ch2],
          title: 'Thesis',
          style: style,
        );
        final texts = doc.blocks.map((b) => b.text).toList();
        // Front matter once, before the first chapter.
        expect(texts.where((t) => t == 'List of figures'), hasLength(1));
        expect(texts.where((t) => t == 'List of tables'), hasLength(1));
        final intro = texts.indexOf('Intro');
        expect(texts.indexOf('List of figures'), lessThan(intro));
        expect(texts.indexOf('List of tables'), lessThan(intro));
        expect(texts, contains('Figure 1.1  Place fields.'));
        expect(texts, contains('Figure 2.1  Setup, cf. Table 2.1.'));
        expect(texts, contains('Table 2.1  Animals.'));
        // Chapter numbering and cross-chapter references.
        expect(texts, contains('Figure 1.1. Place fields.'));
        expect(texts, contains('See Figure 2.1 and Figure 1.1.'));
        expect(texts, contains('Table 2.1. Animals.'));
        expect(
          doc.blocks.where((b) => b.kind == BlockKind.caption),
          hasLength(3),
        );
      });
    }

    test('extra front matter follows the lists, once', () async {
      final doc = await buildExportDoc(
        db,
        [ch1, ch2],
        title: 'T',
        extraFrontMatter: const [
          ExportBlock(BlockKind.heading2, [Run('List of abbreviations')]),
        ],
      );
      final texts = doc.blocks.map((b) => b.text).toList();
      expect(texts.where((t) => t == 'List of abbreviations'), hasLength(1));
      expect(
        texts.indexOf('List of abbreviations'),
        greaterThan(texts.indexOf('List of tables')),
      );
      expect(
        texts.indexOf('List of abbreviations'),
        lessThan(texts.indexOf('Intro')),
      );
    });

    test('no figures, no front matter', () async {
      final doc = await buildExportDoc(db, [
        ExportNote('A', body('x')),
        ExportNote('B', body('y')),
      ], title: 'T');
      expect(doc.blocks.map((b) => b.text), ['A', 'x', 'B', 'y']);
    });

    test('markdown renders the caption in bold', () async {
      final doc = await buildExportDoc(db, [ch1], title: '');
      expect(exportToMarkdown(doc), startsWith('**Figure 1.** Place fields.'));
    });
  });
}

/// Stored content as the editor saves it (normalised).
String encodeStored(String stored) =>
    encodeNoteContent2(Document.fromJson(jsonDecode(stored) as List));

String encodeNoteContent2(Document d) => jsonEncode(d.toDelta().toJson());
