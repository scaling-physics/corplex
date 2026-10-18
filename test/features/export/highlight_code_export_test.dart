import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/notes/note_markdown.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

final _ops = <Map<String, Object?>>[
  {'insert': 'Read '},
  {
    'insert': 'this',
    'attributes': {'background': '#F5E39A'},
  },
  {'insert': ' first\n'},
  {'insert': 'let x = 1;'},
  {
    'insert': '\n',
    'attributes': {'code-block': true},
  },
  {'insert': 'print(x)'},
  {
    'insert': '\n',
    'attributes': {'code-block': true},
  },
  {'insert': 'After\n'},
];

void main() {
  late AppDatabase db;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  Future<ExportDoc> build(List<Map<String, Object?>> ops) =>
      buildExportDoc(db, [ExportNote('T', _delta(ops))], title: 'T');

  test('note Markdown: ==highlight== and one fence per code block', () {
    final md = noteToMarkdown(title: '', content: _delta(_ops));
    expect(md, 'Read ==this== first\n```\nlet x = 1;\nprint(x)\n```\nAfter\n');
  });

  test('export Markdown agrees', () async {
    final md = exportToMarkdown(await build(_ops));
    expect(md, contains('Read ==this== first'));
    expect(md, contains('```\nlet x = 1;\nprint(x)\n```'));
    expect(md, contains('After'));
  });

  test('DOCX: shaded highlight run, Consolas shaded code paragraphs', () async {
    final bytes = exportToDocx(await build(_ops));
    final xml = utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
          as List<int>,
    );
    expect(xml, contains('w:fill="F5E39A"'));
    expect(RegExp('<w:pPr><w:shd[^>]*/>.*?</w:pPr>').allMatches(xml).length, 2);
    expect(xml, contains('Consolas'));
    expect('<w:r>'.allMatches(xml).length, '</w:r>'.allMatches(xml).length);
  });

  test('PDF: highlight and code blocks, even with non-Latin-1 text', () async {
    Future<ByteData> fromDisk(String asset) async =>
        ByteData.sublistView(File(asset).readAsBytesSync());
    final doc = await build([
      ..._ops,
      {'insert': 'データ → café “x”'},
      {
        'insert': '\n',
        'attributes': {'code-block': true},
      },
    ]);
    final pdf = await exportToPdf(doc, loadFont: fromDisk);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    final raw = latin1.decode(pdf);
    expect(raw, contains('Courier'));
  });
}
