import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/docx_export.dart';
import 'package:corplex/features/export/export_actions.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/markdown_export.dart';
import 'package:corplex/features/export/pdf_export.dart';
import 'package:corplex/features/library/citation_formatter.dart';

String _delta(List<Map<String, Object?>> ops) => jsonEncode(ops);

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
            venue: const Value('NeurIPS'),
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

  final content = _delta([
    {'insert': 'Intro'},
    {
      'insert': '\n',
      'attributes': {'header': 1},
    },
    {'insert': 'Transformers '},
    {
      'insert': 'rock',
      'attributes': {'bold': true},
    },
    {'insert': ' [@vaswani2017] & <more> [@devlin2019] [@missing].\n'},
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
    {'insert': 'a quote'},
    {
      'insert': '\n',
      'attributes': {'blockquote': true},
    },
    {'insert': 'See '},
    {
      'insert': 'the site',
      'attributes': {'link': 'https://example.com'},
    },
    {'insert': ' and '},
    {
      'insert': 'a note',
      'attributes': {'link': 'corplex://note/x'},
    },
    {'insert': '\n'},
  ]);

  Future<ExportDoc> build(CitationStyle style) => buildExportDoc(
    db,
    [ExportNote('My “Review”', content)],
    title: 'My “Review”',
    style: style,
  );

  test(
    'citations become in-text references and a reference list is appended',
    () async {
      final doc = await build(CitationStyle.apa);
      final text = doc.blocks.map((b) => b.text).join('\n');
      expect(text, contains('(Vaswani & Shazeer, 2017)'));
      expect(text, contains('(Devlin, 2019)'));
      expect(
        text,
        contains('[@missing]'),
        reason: 'unknown keys are left as written',
      );
      expect(
        doc.blocks.where((b) => b.kind == BlockKind.heading2).single.text,
        'References',
      );
      final refs = doc.blocks
          .skipWhile((b) => b.text != 'References')
          .skip(1)
          .map((b) => b.text)
          .toList();
      expect(refs, hasLength(2));
      expect(refs.first, startsWith('Devlin'));
    },
  );

  test(
    'a reference list already written in the note is replaced, not doubled',
    () async {
      final withOld = _delta([
        {'insert': 'Body [@devlin2019]\n'},
        {'insert': 'References'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'stale entry\n'},
      ]);
      final doc = await buildExportDoc(db, [
        ExportNote('T', withOld),
      ], title: 'T');
      final text = doc.blocks.map((b) => b.text).join('\n');
      expect(text, isNot(contains('stale entry')));
      expect('References'.allMatches(text), hasLength(1));
    },
  );

  test('IEEE numbers citations in order of first use', () async {
    final doc = await build(CitationStyle.ieee);
    final text = doc.blocks.map((b) => b.text).join('\n');
    expect(text, contains('[1] & <more> [2]'));
    expect(doc.blocks.last.text, startsWith('[2] '));
  });

  test('several notes become chapters under one reference list', () async {
    final doc = await buildExportDoc(db, [
      ExportNote(
        'One',
        _delta([
          {'insert': 'x [@vaswani2017]\n'},
        ]),
      ),
      ExportNote(
        'Two',
        _delta([
          {'insert': 'y [@vaswani2017] [@devlin2019]\n'},
        ]),
      ),
    ], title: 'Both');
    expect(
      doc.blocks.where((b) => b.kind == BlockKind.heading1).map((b) => b.text),
      ['One', 'Two'],
    );
    expect(doc.blocks.where((b) => b.text == 'References'), hasLength(1));
    expect(doc.blocks.last.text, isNot(''));
  });

  test(
    'Markdown keeps structure, external links, drops internal ones',
    () async {
      final md = exportToMarkdown(await build(CitationStyle.apa));
      expect(
        md,
        startsWith(
          '# My “Review”\n\n## Intro\n\nTransformers **rock** (Vaswani & Shazeer, 2017)',
        ),
      );
      expect(md, contains('1. first\n2. second'));
      expect(md, contains('> a quote'));
      expect(md, contains('[the site](https://example.com) and a note'));
      expect(md, contains('### References'));
    },
  );

  test(
    'DOCX is a valid package with escaped text and the right styles',
    () async {
      final bytes = exportToDocx(await build(CitationStyle.apa));
      final zip = ZipDecoder().decodeBytes(bytes);
      for (final part in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
      ]) {
        expect(zip.findFile(part), isNotNull, reason: part);
      }
      final xml = utf8.decode(zip.findFile('word/document.xml')!.content);
      expect(xml, contains('w:val="Title"'));
      expect(xml, contains('w:val="Heading1"'));
      expect(xml, contains('w:val="Quote"'));
      expect(xml, contains('&amp; &lt;more&gt;'), reason: 'XML-escaped');
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('the site (https://example.com)'));
      // Every opened tag is closed: a cheap well-formedness check.
      expect('<w:p>'.allMatches(xml).length, '</w:p>'.allMatches(xml).length);
      expect('<w:r>'.allMatches(xml).length, '</w:r>'.allMatches(xml).length);
    },
  );

  test(
    'PDF renders with the embedded font, curly quotes and accents included',
    () async {
      final doc = await buildExportDoc(db, [
        ExportNote(
          'Zoë’s “notes”',
          _delta([
            {'insert': 'Café – naïve “quotes” [@devlin2019]\n'},
          ]),
        ),
      ], title: 'Zoë’s “notes”');
      Future<ByteData> fromDisk(String asset) async =>
          ByteData.sublistView(File(asset).readAsBytesSync());
      final pdf = await exportToPdf(doc, loadFont: fromDisk);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(
        pdf.length,
        greaterThan(1500),
        reason: 'a real, font-bearing document',
      );
    },
  );

  test('PDF sets italic and bold italic in the real italic faces', () async {
    Future<ByteData> fromDisk(String asset) async =>
        ByteData.sublistView(File(asset).readAsBytesSync());
    Future<Set<String>> render(List<Map<String, Object?>> ops) async {
      final doc = await buildExportDoc(db, [
        ExportNote('T', _delta(ops)),
      ], title: 'T');
      final pdf = latin1.decode(await exportToPdf(doc, loadFont: fromDisk));
      return {
        for (final m in RegExp(r'/BaseFont */([A-Za-z-]+)').allMatches(pdf))
          m[1]!,
      };
    }

    final plain = await render([
      {'insert': 'Plain words\n'},
    ]);
    expect(plain, {'Roboto-Regular', 'Roboto-Bold'});

    final italic = await render([
      {
        'insert': 'Leaning',
        'attributes': {'italic': true},
      },
      {
        'insert': ' and strong',
        'attributes': {'italic': true, 'bold': true},
      },
      {'insert': '\n'},
    ]);
    expect(italic, containsAll(['Roboto-Italic', 'Roboto-BoldItalic']));
  });

  test('files are written with safe names', () async {
    expect(
      exportFileName('My “Review”: part 1/2', ExportFormat.word),
      'My Review part 12.docx',
    );
    expect(exportFileName('   ', ExportFormat.pdf), 'Corplex export.pdf');
    final dir = Directory.systemTemp.createTempSync('export');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = await writeExport(
      await build(CitationStyle.mla),
      ExportFormat.markdown,
      dir,
    );
    expect(file.path, endsWith('My Review.md'));
    expect(file.readAsStringSync(), contains('(Vaswani and Shazeer)'));
  });
}
