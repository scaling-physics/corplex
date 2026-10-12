import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

String _delta(List<Map<String, dynamic>> ops) => jsonEncode(ops);

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() {
    db = AppDatabase.inMemoryForTesting();
    tmp = Directory.systemTemp.createTempSync('vault_test');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Map<String, String> texts(Archive a) => {
    for (final f in a.files)
      if (f.isFile) f.name: utf8.decode(f.content, allowMalformed: true),
  };

  test(
    'exports notes, papers, links, highlights, bib and attachments',
    () async {
      final png = File('${tmp.path}/1_diagram.png')
        ..writeAsBytesSync([1, 2, 3]);
      final mp3 = File('${tmp.path}/2_Audio_Overview.mp3')
        ..writeAsBytesSync([4, 5]);
      final pdf = File('${tmp.path}/3_paper.pdf')..writeAsBytesSync([9]);

      await db
          .into(db.folders)
          .insert(
            FoldersCompanion.insert(
              id: const Value('f1'),
              name: 'Thesis: Ch/1',
            ),
          );
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: const Value('t1'), name: 'ml'));
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(id: const Value('pr1'), name: 'Review'),
          );
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Attention Is All You Need',
              authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
              year: const Value(2017),
              venue: const Value('NeurIPS'),
              doi: const Value('10.5555/3295222'),
              citekey: const Value('vaswani2017'),
              pdfPath: Value(pdf.path),
              readingStatus: const Value(ReadingStatus.done),
              rating: const Value(4),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n2'),
              title: const Value('Other note'),
              content: Value(
                _delta([
                  {'insert': 'hi\n'},
                ]),
              ),
              createdAt: Value(DateTime(2026, 1, 1)),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Main: note?'),
              folderId: const Value('f1'),
              createdAt: Value(DateTime(2026, 1, 2)),
              content: Value(
                _delta([
                  {'insert': 'See '},
                  {
                    'insert': 'Other note',
                    'attributes': {'link': 'corplex://note/n2'},
                  },
                  {'insert': ' and [@vaswani2017] or [@nope]. '},
                  {
                    'insert': '— p. 3',
                    'attributes': {'link': 'corplex://paper/p1?page=3'},
                  },
                  {'insert': ' '},
                  {
                    'insert': '▸ 12:34',
                    'attributes': {'link': 'corplex://audio/a1?t=754'},
                  },
                  {'insert': '\n'},
                ]),
              ),
            ),
          );
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1'));
      await db
          .into(db.projectNotes)
          .insert(ProjectNotesCompanion.insert(projectId: 'pr1', noteId: 'n1'));
      await db
          .into(db.projectPapers)
          .insert(
            ProjectPapersCompanion.insert(projectId: 'pr1', paperId: 'p1'),
          );
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: const Value('a0'),
              noteId: const Value('n1'),
              type: AttachmentType.image,
              path: Value(png.path),
              title: const Value('diagram.png'),
            ),
          );
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: const Value('a1'),
              noteId: const Value('n1'),
              type: AttachmentType.podcast,
              path: Value(mp3.path),
            ),
          );
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              paperId: 'p1',
              pageNumber: 3,
              quote: 'Attention is all\nyou need',
              rectsJson: '[]',
              comment: const Value('Key claim'),
            ),
          );

      final r = await buildVaultArchive(db);
      final t = texts(r.archive);

      final noteKey = 'Corplex/Notes/Thesis Ch 1/Main note.md';
      expect(t.keys, contains(noteKey));
      expect(t.keys, contains('Corplex/Notes/Other note.md'));
      final paperKey =
          'Corplex/Papers/@vaswani2017 Attention Is All You Need.md';
      expect(t.keys, contains(paperKey));

      final note = t[noteKey]!;
      expect(note, startsWith('---\nid: "n1"\n'));
      expect(note, contains('tags:\n  - "ml"'));
      expect(note, contains('projects:\n  - "Review"'));
      expect(
        note,
        contains('papers:\n  - "[[@vaswani2017 Attention Is All You Need]]"'),
      );
      expect(note, contains('# Main: note?'));
      expect(note, contains('See [[Other note]] and '));
      expect(
        note,
        contains('[[@vaswani2017 Attention Is All You Need|@vaswani2017]]'),
      );
      expect(note, contains('[@nope]'));
      expect(
        note,
        contains('[[@vaswani2017 Attention Is All You Need|— p. 3]]'),
      );
      expect(note, contains('▸ 12:34'));
      expect(note, isNot(contains('corplex://')));
      expect(note, contains('![[Attachments/diagram.png]]'));
      expect(note, contains('[[Attachments/Audio Overview.mp3]]'));

      final paper = t[paperKey]!;
      expect(paper, contains('citekey: "vaswani2017"'));
      expect(paper, contains('year: 2017'));
      expect(paper, contains('status: "done"'));
      expect(paper, contains('rating: 4'));
      expect(paper, contains('  - "Ashish Vaswani"'));
      expect(paper, contains('### p. 3'));
      expect(paper, contains('> Attention is all\n> you need\n> — p. 3'));
      expect(paper, contains('Key claim'));

      expect(t['Corplex/references.bib'], contains('@article{vaswani2017,'));

      expect(
        r.archive.files.map((f) => f.name),
        contains('Corplex/Attachments/diagram.png'),
      );
      expect(t.keys.any((k) => k.endsWith('.pdf')), isFalse);
      expect(paper, isNot(contains('PDF:')));

      final withPdf = texts(
        (await buildVaultArchive(db, includePdfs: true)).archive,
      );
      expect(
        withPdf.keys,
        contains(
          'Corplex/Attachments/vaswani2017 Attention Is All You Need.pdf',
        ),
      );
      expect(
        withPdf[paperKey],
        contains(
          'PDF: [[Attachments/vaswani2017 Attention Is All You Need.pdf]]',
        ),
      );
    },
  );

  test('missing files are skipped without broken links', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(id: const Value('n1'), title: const Value('A')),
        );
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            noteId: const Value('n1'),
            type: AttachmentType.image,
            path: const Value('/nonexistent/x.png'),
          ),
        );
    final t = texts((await buildVaultArchive(db)).archive);
    expect(t['Corplex/Notes/A.md'], isNot(contains('Attachments')));
  });

  test('file names are sanitised and de-duplicated stably', () {
    expect(
      sanitizeFileName('a/b:c*d?e"f<g>h|i#j^k[l]'),
      'a b c d e f g h i j k l',
    );
    expect(sanitizeFileName('  ..hidden. '), 'hidden');
    expect(sanitizeFileName('CON'), '_CON');
    expect(sanitizeFileName('///'), 'Untitled');
    expect(sanitizeFileName('x' * 200).length, 80);

    final items = [
      NameRequest(id: 'bbbbbbbb-1', base: 'Idea', created: DateTime(2026, 2)),
      NameRequest(id: 'aaaaaaaa-1', base: 'idea', created: DateTime(2026, 1)),
      NameRequest(id: 'cccccccc-1', base: 'Other', created: DateTime(2026, 3)),
    ];
    final a = assignFileNames(items);
    expect(a['aaaaaaaa-1'], 'idea.md');
    expect(a['bbbbbbbb-1'], 'Idea (bbbbbbbb).md');
    expect(a['cccccccc-1'], 'Other.md');
    // Same result whatever the input order.
    expect(assignFileNames(items.reversed.toList()), a);
  });
}
