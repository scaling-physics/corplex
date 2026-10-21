import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/note_markdown.dart';
import 'package:corplex/features/notes/note_sections.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

String _ops(List<Object> ops) => jsonEncode(ops);

Map<String, Object> _embed(String link) => {
  'insert': {noteEmbedType: noteEmbedData(link)},
};

List<Object> _heading(String text, [int level = 1]) => [
  {'insert': text},
  {
    'insert': '\n',
    'attributes': {'header': level},
  },
];

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.inMemoryForTesting());
  tearDown(() => db.close());

  Future<void> note(
    String id,
    String title,
    String content, {
    String? aliases,
  }) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(content),
          aliases: Value(aliases),
        ),
      );

  final bodyB = _ops([
    ..._heading('Methods'),
    {'insert': 'We counted spikes. ^m1\n'},
    ..._heading('Results'),
    {'insert': 'It worked.\n'},
  ]);

  test('an embedded note is written out in place, markers dropped', () async {
    await note('b', 'B', bodyB);
    final host = _ops([
      {'insert': 'Before.\n'},
      _embed(noteLink('b')),
      {'insert': '\nAfter.\n'},
    ]);
    final doc = await buildExportDoc(db, [
      ExportNote('A', host, id: 'a'),
    ], title: 'A');
    final text = doc.blocks.map((b) => b.text).toList();
    expect(text, [
      'Before.',
      'Methods',
      'We counted spikes.',
      'Results',
      'It worked.',
      'After.',
    ]);
  });

  test('a heading or a paragraph can be embedded alone', () async {
    await note('b', 'B', bodyB);
    final host = _ops([
      _embed(noteLink('b', heading: 'results')),
      {'insert': '\n'},
      _embed(noteLink('b', block: 'm1')),
      {'insert': '\n'},
    ]);
    final doc = await buildExportDoc(db, [ExportNote('A', host)], title: 'A');
    expect(doc.blocks.map((b) => b.text), [
      'Results',
      'It worked.',
      'We counted spikes.',
    ]);
  });

  test('embeds that point back are expanded once, not forever', () async {
    final a = _ops([
      {'insert': 'In A.\n'},
      _embed(noteLink('b')),
      {'insert': '\n'},
    ]);
    final b = _ops([
      {'insert': 'In B.\n'},
      _embed(noteLink('a')),
      {'insert': '\n'},
    ]);
    await note('a', 'A', a);
    await note('b', 'B', b);
    final doc = await buildExportDoc(db, [
      ExportNote('A', a, id: 'a'),
    ], title: 'A');
    expect(doc.blocks.map((b) => b.text), ['In A.', 'In B.']);

    // Without the host's id the cycle is still cut after one lap.
    final anon = await buildExportDoc(db, [ExportNote('A', a)], title: 'A');
    expect(anon.blocks.map((b) => b.text), ['In A.', 'In B.', 'In A.']);
  });

  test('embeds nest three levels deep at most', () async {
    for (var i = 1; i <= 5; i++) {
      await note(
        'n$i',
        'N$i',
        _ops([
          {'insert': 'level $i\n'},
          if (i < 5) ...[
            _embed(noteLink('n${i + 1}')),
            {'insert': '\n'},
          ],
        ]),
      );
    }
    final stored = await inlineNoteEmbeds(
      db,
      _ops([
        {'insert': 'top\n'},
        _embed(noteLink('n1')),
        {'insert': '\n'},
      ]),
    );
    final text = jsonDecode(stored)
        .map((op) => op['insert'])
        .whereType<String>()
        .join();
    expect(text, 'top\nlevel 1\nlevel 2\nlevel 3\n');
  });

  test('missing and locked targets leave nothing behind', () async {
    await note('l', 'Locked', 'corplex-locked:v1:k:AAAA');
    final host = _ops([
      {'insert': 'x\n'},
      _embed(noteLink('l')),
      {'insert': '\n'},
      _embed(noteLink('gone')),
      {'insert': '\ny\n'},
    ]);
    final doc = await buildExportDoc(db, [ExportNote('A', host)], title: 'A');
    expect(doc.blocks.map((b) => b.text).where((t) => t.isNotEmpty), [
      'x',
      'y',
    ]);
  });

  test('a note exports without its block ids', () async {
    final doc = await buildExportDoc(db, [ExportNote('B', bodyB)], title: 'B');
    expect(doc.blocks.map((b) => b.text).join('|'), isNot(contains('^m1')));
  });

  test('noteToMarkdown keeps block ids and writes embeds as wiki embeds', () {
    final md = noteToMarkdown(
      title: '',
      content: _ops([
        {'insert': 'Claim. ^m1\n'},
        _embed(noteLink('b', heading: 'Results')),
        {'insert': '\n'},
      ]),
      embedLine: (link) => '![[B#Results]]',
    );
    expect(md, contains('Claim. ^m1'));
    expect(md, contains('![[B#Results]]'));
    expect(
      noteToMarkdown(title: '', content: bodyB, keepBlockIds: false),
      isNot(contains('^m1')),
    );
  });

  test(
    'the vault links to headings and blocks, embeds, and lists aliases',
    () async {
      await note('b', 'Target', bodyB, aliases: 'Goal; Aim');
      await note(
        'a',
        'Host',
        _ops([
          {'insert': 'See '},
          {
            'insert': 'Target › Results',
            'attributes': {'link': noteLink('b', heading: 'Results')},
          },
          {'insert': ' and '},
          {
            'insert': 'Target › We counted spikes.',
            'attributes': {'link': noteLink('b', block: 'm1')},
          },
          {'insert': ' and '},
          {
            'insert': 'the goal',
            'attributes': {'link': noteLink('b', heading: 'Methods')},
          },
          {'insert': '.\nMine. ^own\n'},
          _embed(noteLink('b')),
          {'insert': '\n'},
          _embed(noteLink('b', heading: 'Results')),
          {'insert': '\n'},
          _embed(noteLink('b', block: 'm1')),
          {'insert': '\n'},
        ]),
      );
      final archive = (await buildVaultArchive(db)).archive;
      final texts = {
        for (final f in archive.files)
          if (f.isFile) f.name: utf8.decode(f.content as List<int>),
      };
      final host = texts['Corplex/Notes/Host.md']!;
      expect(host, contains('[[Target#Results]]'));
      expect(host, contains('[[Target#^m1]]'));
      expect(host, contains('[[Target#Methods|the goal]]'));
      expect(host, contains('Mine. ^own'));
      expect(host, contains('![[Target]]'));
      expect(host, contains('![[Target#Results]]'));
      expect(host, contains('![[Target#^m1]]'));
      final target = texts['Corplex/Notes/Target.md']!;
      expect(target, contains('aliases:\n  - "Goal"\n  - "Aim"'));
      expect(target, contains('We counted spikes. ^m1'));
      expect(host, isNot(contains('aliases:')));
    },
  );
}
