// Fills a database with a realistic large library, for the performance
// tests (`test/perf/`) and `integration_test/perf_test.dart`.
//
// Pure data: no Flutter bindings, so it also runs from a plain `dart` test.
import 'dart:convert';
import 'dart:math';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:drift/drift.dart';

class LibrarySize {
  const LibrarySize({
    this.papers = 1500,
    this.notes = 3000,
    this.highlights = 20000,
    this.folders = 25,
    this.tags = 40,
    this.projects = 8,
  });

  final int papers;
  final int notes;
  final int highlights;
  final int folders;
  final int tags;
  final int projects;
}

const _words = [
  'neural',
  'cortex',
  'learning',
  'memory',
  'attention',
  'transformer',
  'hippocampus',
  'synaptic',
  'plasticity',
  'network',
  'gradient',
  'language',
  'model',
  'perception',
  'dopamine',
  'reward',
  'oscillation',
  'theta',
  'decision',
  'prefrontal',
  'imaging',
  'optogenetic',
  'behaviour',
  'sleep',
  'consolidation',
  'representation',
  'inference',
  'bayesian',
  'sparse',
  'coding',
  'grid',
  'place',
  'cells',
  'dynamics',
  'population',
  'task',
];
const _surnames = [
  'Vaswani',
  'Kandel',
  'Moser',
  'Okeefe',
  'Hinton',
  'LeCun',
  'Bengio',
  'Schultz',
  'Squire',
  'Buzsaki',
  'Miller',
  'Cohen',
  'Friston',
  'Dayan',
  'Sejnowski',
  'Poldrack',
  'Gallant',
  'Olshausen',
  'Tolias',
  'Harris',
];
const _givens = ['Ashish', 'Eric', 'May-Britt', 'John', 'Geoffrey', 'Yann'];
const _venues = ['Nature', 'Neuron', 'Science', 'NeurIPS', 'eLife', 'Cell'];

class SeededLibrary {
  SeededLibrary({
    required this.paperIds,
    required this.noteIds,
    required this.folderIds,
    required this.tagIds,
    required this.projectIds,
    required this.pdfPaperIds,
  });

  final List<String> paperIds;
  final List<String> noteIds;
  final List<String> folderIds;
  final List<String> tagIds;
  final List<String> projectIds;

  /// Papers given a `pdf_path` (see `pdfPaths`).
  final List<String> pdfPaperIds;
}

String _sentence(Random r, int words) =>
    [for (var i = 0; i < words; i++) _words[r.nextInt(_words.length)]]
        .join(' ');

String _title(Random r) {
  final s = _sentence(r, 4 + r.nextInt(6));
  return s[0].toUpperCase() + s.substring(1);
}

/// A note body (Quill Delta JSON): a heading, a few paragraphs, sometimes a
/// citation, a drawing and a table.
String noteBody(Random r, List<String> citekeys, {bool big = false}) {
  final ops = <Map<String, Object?>>[
    {'insert': _title(r)},
    {
      'insert': '\n',
      'attributes': {'header': 2},
    },
  ];
  final paragraphs = big ? 400 : 3 + r.nextInt(4);
  for (var i = 0; i < paragraphs; i++) {
    var text = '${_sentence(r, 25 + r.nextInt(40))}.';
    if (citekeys.isNotEmpty && r.nextInt(3) == 0) {
      text += ' [@${citekeys[r.nextInt(citekeys.length)]}]';
    }
    ops.add({'insert': '$text\n'});
  }
  if (big || r.nextInt(8) == 0) {
    final strokes = [
      for (var s = 0; s < (big ? 40 : 8); s++)
        {
          't': 'p',
          'c': 'ff1b1b1b',
          'w': 0.004,
          'p': [
            for (var p = 0; p < 90; p++)
              ...[
                r.nextDouble().toStringAsFixed(4),
                r.nextDouble().toStringAsFixed(4),
                '0.5',
              ].map(double.parse),
          ],
        },
    ];
    ops.add({
      'insert': {
        'sketch': jsonEncode({'v': 1, 'a': 0.6, 's': strokes, 't': 'hello'}),
      },
    });
    ops.add({'insert': '\n'});
  }
  if (big || r.nextInt(10) == 0) {
    ops.add({
      'insert': {
        'table': jsonEncode({
          'v': 1,
          'h': true,
          'r': [
            for (var row = 0; row < 4; row++)
              [for (var c = 0; c < 3; c++) _sentence(r, 2)],
          ],
        }),
      },
    });
    ops.add({'insert': '\n'});
  }
  return jsonEncode(ops);
}

/// Inserts a library of [size] into [db]. Deterministic for a [seed].
/// [pdfPaths] (optional) are given, in order, to the first papers.
Future<SeededLibrary> seedLibrary(
  AppDatabase db, {
  LibrarySize size = const LibrarySize(),
  int seed = 7,
  List<String> pdfPaths = const [],
  DateTime? now,
}) async {
  final r = Random(seed);
  final base = (now ?? DateTime(2026, 10, 1)).millisecondsSinceEpoch ~/ 1000;
  DateTime at(int secondsAgo) =>
      DateTime.fromMillisecondsSinceEpoch((base - secondsAgo) * 1000);

  final folderIds = [for (var i = 0; i < size.folders; i++) 'folder-$i'];
  final tagIds = [for (var i = 0; i < size.tags; i++) 'tag-$i'];
  final projectIds = [for (var i = 0; i < size.projects; i++) 'project-$i'];
  final paperIds = [for (var i = 0; i < size.papers; i++) 'paper-$i'];
  final noteIds = [for (var i = 0; i < size.notes; i++) 'note-$i'];
  final pdfPaperIds = <String>[];
  final citekeys = <String>[];

  await db.transaction(() async {
    await db.batch((b) {
      b.insertAll(db.folders, [
        for (var i = 0; i < folderIds.length; i++)
          FoldersCompanion.insert(id: Value(folderIds[i]), name: 'Folder $i'),
      ]);
      b.insertAll(db.tags, [
        for (var i = 0; i < tagIds.length; i++)
          TagsCompanion.insert(id: Value(tagIds[i]), name: 'tag$i'),
      ]);
      b.insertAll(db.projects, [
        for (var i = 0; i < projectIds.length; i++)
          ProjectsCompanion.insert(
            id: Value(projectIds[i]),
            name: 'Chapter set $i',
          ),
      ]);
    });

    final papers = <PapersCompanion>[];
    for (var i = 0; i < size.papers; i++) {
      final family = _surnames[r.nextInt(_surnames.length)];
      final year = 1995 + r.nextInt(31);
      final key = '${family.toLowerCase()}$year${i < 400 ? '' : 'x$i'}';
      if (i < 400) citekeys.add(key);
      final pdf = i < pdfPaths.length ? pdfPaths[i] : null;
      if (pdf != null) pdfPaperIds.add(paperIds[i]);
      papers.add(
        PapersCompanion.insert(
          id: Value(paperIds[i]),
          title: _title(r),
          authors: Value(
            [
              for (var a = 0; a < 1 + r.nextInt(5); a++)
                '${_surnames[r.nextInt(_surnames.length)]}, '
                    '${_givens[r.nextInt(_givens.length)]}',
            ].join('; '),
          ),
          year: Value(year),
          venue: Value(_venues[r.nextInt(_venues.length)]),
          doi: Value('10.${1000 + r.nextInt(8000)}/x.$i'),
          citekey: Value(i < 400 ? key : null),
          pdfPath: Value(pdf),
          pageCount: Value(pdf == null ? null : 12),
          readingStatus: Value(
            r.nextInt(3) == 0 ? ReadingStatus.values[r.nextInt(3)] : null,
          ),
          createdAt: Value(at(i * 60)),
          updatedAt: Value(at(i * 60)),
        ),
      );
    }
    await db.batch((b) => b.insertAll(db.papers, papers));

    final notes = <NotesCompanion>[];
    for (var i = 0; i < size.notes; i++) {
      notes.add(
        NotesCompanion.insert(
          id: Value(noteIds[i]),
          title: Value(_title(r)),
          content: Value(noteBody(r, citekeys)),
          folderId: Value(
            r.nextInt(3) == 0 ? folderIds[i % folderIds.length] : null,
          ),
          pinned: Value(i % 150 == 0),
          createdAt: Value(at(i * 90)),
          updatedAt: Value(at(i * 90)),
        ),
      );
    }
    await db.batch((b) => b.insertAll(db.notes, notes));

    await db.batch((b) {
      b.insertAll(db.noteTags, [
        for (var i = 0; i < size.notes; i += 2)
          NoteTagsCompanion.insert(
            noteId: noteIds[i],
            tagId: tagIds[i % tagIds.length],
          ),
      ], mode: InsertMode.insertOrIgnore);
      b.insertAll(db.projectNotes, [
        for (var i = 0; i < size.notes; i += 6)
          ProjectNotesCompanion.insert(
            projectId: projectIds[i % projectIds.length],
            noteId: noteIds[i],
          ),
      ], mode: InsertMode.insertOrIgnore);
      b.insertAll(db.projectPapers, [
        for (var i = 0; i < size.papers; i += 4)
          ProjectPapersCompanion.insert(
            projectId: projectIds[i % projectIds.length],
            paperId: paperIds[i],
          ),
      ], mode: InsertMode.insertOrIgnore);
      b.insertAll(db.notePaperRefs, [
        for (var i = 0; i < size.notes; i += 3)
          NotePaperRefsCompanion.insert(
            noteId: noteIds[i],
            paperId: paperIds[(i * 7) % size.papers],
          ),
      ], mode: InsertMode.insertOrIgnore);
      b.insertAll(db.attachments, [
        for (var i = 0; i < size.notes; i += 5)
          AttachmentsCompanion.insert(
            noteId: Value(noteIds[i]),
            type: i % 2 == 0 ? AttachmentType.image : AttachmentType.podcast,
            title: Value('Attachment $i'),
            path: Value('/tmp/none/$i.bin'),
            createdAt: Value(at(i * 30)),
          ),
        for (var i = 0; i < size.papers; i += 5)
          AttachmentsCompanion.insert(
            paperId: Value(paperIds[i]),
            type: AttachmentType.link,
            url: Value('https://example.org/$i'),
            createdAt: Value(at(i * 30 + 7)),
          ),
      ]);
    });

    final highlights = <HighlightsCompanion>[];
    for (var i = 0; i < size.highlights; i++) {
      highlights.add(
        HighlightsCompanion.insert(
          id: Value('hl-$i'),
          paperId: paperIds[i % size.papers],
          pageNumber: 1 + r.nextInt(12),
          quote: '${_sentence(r, 12 + r.nextInt(20))}.',
          rectsJson: '[[0.1,0.2,0.8,0.03]]',
          comment: Value(r.nextInt(4) == 0 ? _sentence(r, 8) : null),
          createdAt: Value(at(i * 20)),
          updatedAt: Value(at(i * 20)),
        ),
      );
    }
    await db.batch((b) => b.insertAll(db.highlights, highlights));
  });

  return SeededLibrary(
    paperIds: paperIds,
    noteIds: noteIds,
    folderIds: folderIds,
    tagIds: tagIds,
    projectIds: projectIds,
    pdfPaperIds: pdfPaperIds,
  );
}
