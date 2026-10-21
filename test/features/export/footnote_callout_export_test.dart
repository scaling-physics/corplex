import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/latex_export.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/library/citation_formatter.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

Future<ByteData> _fromDisk(String asset) async =>
    ByteData.sublistView(File(asset).readAsBytesSync());

String _part(Archive a, String name) =>
    utf8.decode(a.findFile(name)!.content as List<int>);

const _quote = {'blockquote': true};

final _content = _delta([
  {'insert': 'Attention'},
  {
    'insert': '\n',
    'attributes': {'header': 1},
  },
  {
    'insert':
        'Transformers^[Introduced in [@vaswani2017]; see \$x_1\$ & more] win. ',
  },
  {
    'insert': 'Again^[Second note]',
    'attributes': {'bold': true},
  },
  {'insert': '.\n'},
  {'insert': '[!warning] Careful here'},
  {'insert': '\n', 'attributes': _quote},
  {'insert': 'Second line of the callout'},
  {'insert': '\n', 'attributes': _quote},
  {'insert': 'After the callout.\n'},
  {'insert': '[!tip]'},
  {'insert': '\n', 'attributes': _quote},
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  });
  tearDown(() => db.close());

  Future<ExportDoc> build({List<ExportNote>? notes}) => buildExportDoc(
    db,
    notes ?? [ExportNote('Note', _content)],
    title: 'Note',
  );

  group('model', () {
    test('footnotes become runs holding their resolved text', () async {
      final doc = await build();
      final foots = [
        for (final b in doc.blocks)
          for (final r in b.runs)
            if (r.footnote != null) r,
      ];
      expect(foots, hasLength(2));
      expect(
        foots.first.footnote!.map((r) => r.text).join(),
        contains('(Vaswani'),
      );
      expect(foots.first.footnote!.any((r) => r.math), isTrue);
      // The footnote's citation is cited: the reference list has it.
      expect(doc.papers.map((p) => p.citekey), ['vaswani2017']);
    });

    test('callout lines are marked; the head keeps a bold label', () async {
      final doc = await build();
      final quotes = doc.blocks
          .where((b) => b.kind == BlockKind.quote)
          .toList();
      expect(quotes, hasLength(3));
      expect(quotes[0].callout!.head, isTrue);
      expect(quotes[0].callout!.type, 'warning');
      expect(quotes[0].text, 'Careful here');
      expect(quotes[0].runs.every((r) => r.bold), isTrue);
      expect(quotes[1].callout!.head, isFalse);
      expect(quotes[1].callout!.type, 'warning');
      expect(quotes[1].text, 'Second line of the callout');
      // No title: the label is the type's name.
      expect(quotes[2].callout!.type, 'tip');
      expect(quotes[2].text, 'Tip');
    });
  });

  group('markdown', () {
    test('keeps ^[…] and > [!type] Title', () async {
      final md = exportToMarkdown(await build());
      expect(md, contains('^[Introduced in (Vaswani'));
      expect(md, contains('^[Second note]'));
      expect(md, contains('> [!warning] Careful here\n> Second line'));
      expect(md, contains('> [!tip]'));
    });
  });

  group('docx', () {
    test('has real footnotes and shaded callouts', () async {
      final doc = await build();
      final zip = ZipDecoder().decodeBytes(exportToDocx(doc));
      final footnotes = _part(zip, 'word/footnotes.xml');
      expect(footnotes, contains('w:type="separator"'));
      expect(footnotes, contains('<w:footnote w:id="1">'));
      expect(footnotes, contains('<w:footnote w:id="2">'));
      expect(footnotes, contains('Second note'));
      expect(footnotes, contains('(Vaswani'));
      expect(footnotes, contains('\$x_1\$'));
      expect(footnotes, contains('&amp; more'));
      final body = _part(zip, 'word/document.xml');
      expect(RegExp('<w:footnoteReference').allMatches(body), hasLength(2));
      expect(body, contains('w:fill="F6E1DD"')); // warning: error tone
      expect(body, contains('w:fill="F3E6DE"')); // tip: tertiary tone
      expect(body, contains('<w:b/>'));
      expect(
        _part(zip, '[Content_Types].xml'),
        contains('/word/footnotes.xml'),
      );
      expect(
        _part(zip, 'word/_rels/document.xml.rels'),
        contains('relationships/footnotes'),
      );
      expect(_part(zip, 'word/styles.xml'), contains('FootnoteReference'));
    });

    test('a note without footnotes gets no footnote parts', () async {
      final doc = await build(
        notes: [
          ExportNote(
            'Plain',
            _delta([
              {'insert': 'Hello\n'},
            ]),
          ),
        ],
      );
      final zip = ZipDecoder().decodeBytes(exportToDocx(doc));
      expect(zip.findFile('word/footnotes.xml'), isNull);
      expect(_part(zip, '[Content_Types].xml'), isNot(contains('footnotes')));
    });
  });

  group('latex', () {
    test('uses \\footnote and a quote with a bold label', () async {
      final tex = buildLatexProject(await build()).main;
      expect(
        tex,
        contains(
          r'\footnote{Introduced in \citep{vaswani2017}; see $x_1$ \& more}',
        ),
      );
      expect(tex, contains(r'\textbf{Again}\footnote{Second note}'));
      expect(tex, contains('\\begin{quote}\n\\textbf{Careful here}'));
      expect(tex, contains(r'\textbf{Tip}'));
    });
  });

  group('pdf', () {
    test('builds with superscripts and a Notes list per chapter', () async {
      final doc = await build(
        notes: [
          ExportNote('One', _content),
          ExportNote(
            'Two',
            _delta([
              {'insert': 'More^[Chapter two note]\n'},
            ]),
          ),
        ],
      );
      final bytes = await exportToPdf(doc, loadFont: _fromDisk);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
      final out = Platform.environment['FOOTNOTE_PDF'];
      if (out != null) File(out).writeAsBytesSync(bytes);
    });

    test('a note without footnotes is unchanged', () async {
      final doc = await build(
        notes: [
          ExportNote(
            'Plain',
            _delta([
              {'insert': '[!note] Just a callout'},
              {'insert': '\n', 'attributes': _quote},
            ]),
          ),
        ],
      );
      final bytes = await exportToPdf(doc, loadFont: _fromDisk);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  test('citation style still resolves for footnotes', () async {
    final doc = await buildExportDoc(
      db,
      [ExportNote('Note', _content)],
      title: 'Note',
      style: CitationStyle.mla,
    );
    final foot = doc.blocks
        .expand((b) => b.runs)
        .firstWhere((r) => r.footnote != null);
    expect(foot.footnote!.map((r) => r.text).join(), contains('Vaswani'));
  });
}
