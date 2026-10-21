import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:corplex/features/markdown_import/markdown_importer.dart';
import 'package:corplex/features/markdown_import/vault_source.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_highlight.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/note_table.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

const _fixture = 'test/fixtures/obsidian_vault';

MemorySourceFile _text(String path, String text) =>
    MemorySourceFile(path, () => utf8.encode(text) as dynamic);

Future<Note> _note(AppDatabase db, String title) async {
  final all = await db.select(db.notes).get();
  return all.firstWhere((n) => n.title == title);
}

/// Every `link` attribute in a note, with the text it covers.
List<(String, String)> _links(Note n) => [
  for (final op in decodeNoteContent(n.content).toDelta().toJson())
    if (op['attributes'] is Map && (op['attributes'] as Map)['link'] != null)
      (op['insert'] as String, (op['attributes'] as Map)['link'] as String),
];

List<Map<String, dynamic>> _ops(Note n) => [
  for (final op in decodeNoteContent(n.content).toDelta().toJson())
    Map<String, dynamic>.from(op as Map),
];

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('md_import_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    db = AppDatabase.inMemoryForTesting();
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('the sample vault', () {
    late MdImportSummary summary;

    setUp(() async {
      final files = await loadVaultDirectory(Directory(_fixture));
      summary = await importMarkdown(db, files);
    });

    test(
      'ignores hidden folders and skips paper pages and locked notes',
      () async {
        final titles =
            (await db.select(db.notes).get()).map((n) => n.title).toList()
              ..sort();
        expect(titles, ['Alpha', 'Alpha', 'Beta', 'Home']);
        expect(summary.notes, 4);
        expect(summary.skipped, 2);
        expect(summary.failed, 0);
        expect(titles, isNot(contains('Old')));
        expect(titles, isNot(contains('A study')));
        expect(titles, isNot(contains('Locked')));
      },
    );

    test('folders come from the path', () async {
      final folders = {
        for (final f in await db.select(db.folders).get()) f.id: f.name,
      };
      final notes = await db.select(db.notes).get();
      String? folderOf(String title, int nth) =>
          folders[notes.where((n) => n.title == title).toList()[nth].folderId];
      expect(folders.values.toSet(), {'Projects', 'Archive'});
      expect((await _note(db, 'Home')).folderId, isNull);
      expect((await _note(db, 'Beta')).folderId, isNotNull);
      expect(folderOf('Beta', 0), 'Projects');
    });

    test('tags and aliases from front matter and the text', () async {
      final home = await _note(db, 'Home');
      final tags = await (db.select(db.tags).join([])).get();
      final names = tags.map((r) => r.readTable(db.tags).name).toSet();
      expect(names, {'research', 'deep learning', 'inbox', 'area/work'});
      final linked = await db.select(db.noteTags).get();
      expect(linked.where((t) => t.noteId == home.id), hasLength(4));
      expect(home.aliases, 'Start; Main page');
      // Tags stay in the text.
      expect(decodeNoteContent(home.content).toPlainText(), contains('#inbox'));
    });

    test(
      'links resolve by title, path, nearest folder, fragment and block',
      () async {
        final notes = await db.select(db.notes).get();
        final projects = {
          for (final f in await db.select(db.folders).get()) f.name: f.id,
        };
        final alphaArchive = notes.firstWhere(
          (n) => n.title == 'Alpha' && n.folderId == projects['Archive'],
        );
        final alphaProjects = notes.firstWhere(
          (n) => n.title == 'Alpha' && n.folderId == projects['Projects'],
        );
        final home = await _note(db, 'Home');
        final beta = await _note(db, 'Beta');

        final homeLinks = _links(home);
        // [[Alpha]] from the root: ambiguous, the first by path wins.
        expect(homeLinks[0], ('Alpha', noteLink(alphaArchive.id)));
        expect(homeLinks[1], ('the beta project', noteLink(beta.id)));
        expect(homeLinks[2], (
          'Alpha › Goals',
          noteLink(alphaArchive.id, heading: 'Goals'),
        ));
        expect(homeLinks[3], (
          'Beta › Beta body line',
          noteLink(beta.id, block: 'key1'),
        ));

        // From Projects/, the one in the same folder wins; a relative .md
        // link with a heading points back at Home.
        final betaLinks = _links(beta);
        expect(betaLinks[0], ('Alpha', noteLink(alphaProjects.id)));
        expect(betaLinks[1], ('Home', noteLink(home.id, heading: 'Home')));

        // Alpha (Projects) links back to Home.
        expect(_links(alphaProjects).single, ('Home', noteLink(home.id)));
      },
    );

    test('unresolved links are text and counted; embeds are cards', () async {
      final home = await _note(db, 'Home');
      expect(summary.unresolved, 1);
      final text = decodeNoteContent(home.content).toPlainText();
      expect(text, contains('Missing note'));
      final embeds = [
        for (final op in _ops(home))
          if (op['insert'] is Map &&
              (op['insert'] as Map).containsKey(noteEmbedType))
            noteEmbedLink((op['insert'] as Map)[noteEmbedType] as String),
      ];
      final alphaArchive = (await db.select(db.notes).get()).firstWhere(
        (n) => n.title == 'Alpha' && n.content.contains('Old alpha'),
      );
      expect(embeds, [noteLink(alphaArchive.id)]);
    });

    test('images and files become attachments in app storage', () async {
      final home = await _note(db, 'Home');
      final atts = await (db.select(
        db.attachments,
      )..where((a) => a.noteId.equals(home.id))).get();
      expect(summary.attachments, 2);
      expect(atts.map((a) => a.type).toSet(), {
        AttachmentType.image,
        AttachmentType.file,
      });
      for (final a in atts) {
        expect(File(a.path!).existsSync(), isTrue);
        expect(a.path, startsWith(tmp.path));
      }
      expect(atts.map((a) => a.title), containsAll(['pic.png', 'paper.pdf']));
      // The embed itself left the text.
      expect(
        decodeNoteContent(home.content).toPlainText(),
        isNot(contains('pic.png')),
      );
    });

    test(
      'formatting, lists, quote, table, code, maths, citation, footnote',
      () async {
        final home = await _note(db, 'Home');
        final ops = _ops(home);
        Map<String, dynamic>? attrs(String text) {
          for (final op in ops) {
            if (op['insert'] == text) {
              return op['attributes'] as Map<String, dynamic>?;
            }
          }
          return null;
        }

        expect(attrs('bold'), {'bold': true});
        expect(attrs('italic'), {'italic': true});
        expect(attrs('gone'), {'strike': true});
        expect(attrs('marked'), {'background': NoteHighlight.yellow.hex});
        final lists = [
          for (final op in ops)
            if (op['insert'] == '\n' &&
                (op['attributes'] as Map?)?['list'] != null)
              op['attributes'],
        ];
        expect(lists, [
          {'list': 'unchecked'},
          {'list': 'checked'},
          {'list': 'bullet', 'indent': 1},
        ]);
        expect(
          ops.any(
            (o) =>
                o['insert'] == '\n' &&
                (o['attributes'] as Map?)?['code-block'] == true,
          ),
          isTrue,
        );
        expect(
          ops.any(
            (o) =>
                o['insert'] == '\n' &&
                (o['attributes'] as Map?)?['blockquote'] == true,
          ),
          isTrue,
        );
        final table = ops.firstWhere(
          (o) =>
              o['insert'] is Map && (o['insert'] as Map).containsKey('table'),
        );
        expect(
          NoteTable.decode((table['insert'] as Map)['table'] as String).rows,
          [
            ['Name', 'Score'],
            ['Ann', '3'],
            ['Bo', '5'],
          ],
        );
        final text = decodeNoteContent(home.content).toPlainText();
        expect(text, contains(r'$x^2$'));
        expect(text, contains('[@smith2020, p. 4]'));
        expect(text, contains('^[The note text.]'));
        expect(text, contains('[!tip] A tip'));
        expect(text, isNot(contains('[^1]')));
      },
    );
  });

  test('re-importing the same vault adds nothing', () async {
    final files = await loadVaultDirectory(Directory(_fixture));
    await importMarkdown(db, files);
    final again = await importMarkdown(
      db,
      await loadVaultDirectory(Directory(_fixture)),
    );
    expect(again.notes, 0);
    expect(again.skipped, 6);
    expect(await db.select(db.notes).get(), hasLength(4));
    expect(await db.select(db.attachments).get(), hasLength(2));
    expect(await db.select(db.folders).get(), hasLength(2));
  });

  test(
    'a changed note imports as a new note; links to unchanged ones hold',
    () async {
      await importMarkdown(db, [
        _text('A.md', 'first'),
        _text('B.md', 'to [[A]]'),
      ]);
      final a = await _note(db, 'A');
      final again = await importMarkdown(db, [
        _text('A.md', 'first'),
        _text('B.md', 'to [[A]] and more'),
      ]);
      expect(again.notes, 1);
      expect(again.skipped, 1);
      final bs = (await db.select(db.notes).get()).where((n) => n.title == 'B');
      final newest = bs.firstWhere((n) => n.content.contains('and more'));
      // The link points at the A that was already there, not a phantom id.
      expect(_links(newest).single.$2, noteLink(a.id));
    },
  );

  test('a zip import strips the top folder', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('MyVault/One.md', 'see [[Two]] ![[pic.png]]'),
      )
      ..addFile(ArchiveFile.string('MyVault/sub/Two.md', '# Two\nbody'))
      ..addFile(ArchiveFile.bytes('MyVault/pic.png', [1, 2, 3]))
      ..addFile(ArchiveFile.string('MyVault/.obsidian/x.md', 'no'))
      ..addFile(ArchiveFile.string('__MACOSX/MyVault/._One.md', 'no'));
    final zip = File(p.join(tmp.path, 'v.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final summary = await importMarkdown(db, loadVaultZip(zip));
    expect(summary.notes, 2);
    expect(summary.attachments, 1);
    final one = await _note(db, 'One');
    final two = await _note(db, 'Two');
    expect(_links(one).single, ('Two', noteLink(two.id)));
    final folder = await (db.select(db.folders)).getSingle();
    expect(folder.name, 'sub');
    expect(two.folderId, folder.id);
  });

  test(
    'loose files: names, front matter dates, aliases as link targets',
    () async {
      await importMarkdown(db, [
        _text(
          'Note.md',
          '---\naliases: [Nick]\ncreated: 2025-05-06T07:08:09Z\n---\nbody',
        ),
        _text('Other.md', 'hello [[nick]] and [[NOTE]]'),
      ]);
      final note = await _note(db, 'Note');
      final other = await _note(db, 'Other');
      expect(note.createdAt.toUtc(), DateTime.utc(2025, 5, 6, 7, 8, 9));
      expect(_links(other), [
        ('Note', noteLink(note.id)),
        ('Note', noteLink(note.id)),
      ]);
    },
  );

  test('nested folders become "A / B"; folders are reused', () async {
    await importMarkdown(db, [
      _text('A/B/One.md', 'x'),
      _text('A/B/Two.md', 'y'),
    ]);
    final folders = await db.select(db.folders).get();
    expect(folders.map((f) => f.name), ['A / B']);
    expect((await _note(db, 'One')).folderId, folders.single.id);
    expect((await _note(db, 'Two')).folderId, folders.single.id);
  });

  test('an existing folder is reused case-insensitively', () async {
    await db.into(db.folders).insert(FoldersCompanion.insert(name: 'ideas'));
    await importMarkdown(db, [_text('Ideas/One.md', 'x')]);
    expect(await db.select(db.folders).get(), hasLength(1));
  });

  test('a paper page is only skipped in a Papers folder or with @', () async {
    final s = await importMarkdown(db, [
      _text('Papers/@k1 Title.md', '---\ncitekey: k1\n---\n# Title'),
      _text('Reading/Zotero note.md', '---\ncitekey: k2\n---\nmy own note'),
    ]);
    expect(s.notes, 1);
    expect(s.skipped, 1);
    expect((await db.select(db.notes).get()).single.title, 'Zotero note');
  });

  test('progress is reported and notes go through drift', () async {
    final seen = <(int, int)>[];
    await importMarkdown(db, [
      _text('A.md', '1'),
      _text('B.md', '2'),
      _text('C.md', '3'),
    ], onProgress: (d, t) => seen.add((d, t)));
    expect(seen.first, (0, 3));
    expect(seen.last, (3, 3));
    final watched = await db.select(db.notes).watch().first;
    expect(watched, hasLength(3));
  });

  test('attachment types', () {
    expect(attachmentTypeForPath('a/x.PNG'), AttachmentType.image);
    expect(attachmentTypeForPath('x.m4a'), AttachmentType.podcast);
    expect(attachmentTypeForPath('x.pdf'), AttachmentType.file);
    expect(attachmentTypeForPath('x.svg'), AttachmentType.file);
  });

  group('round trip through the vault export', () {
    test('what Corplex writes, Corplex reads', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final src = AppDatabase.inMemoryForTesting();
      addTearDown(src.close);

      final pic = File(p.join(tmp.path, 'photo.png'))
        ..writeAsBytesSync(
          File('$_fixture/attachments/pic.png').readAsBytesSync(),
        );

      await src
          .into(src.folders)
          .insert(
            FoldersCompanion.insert(id: const Value('f1'), name: 'Reading'),
          );
      await src
          .into(src.tags)
          .insert(TagsCompanion.insert(id: const Value('t1'), name: 'neuro'));
      await src
          .into(src.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'Attention is all you need',
              authors: const Value('Vaswani, Ashish'),
              year: const Value(2017),
              citekey: const Value('vaswani2017'),
            ),
          );

      String doc(List<Object> ops) => jsonEncode(ops);
      final hi = NoteHighlight.yellow.hex;
      await src
          .into(src.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n-main'),
              title: const Value('Main: ideas'),
              folderId: const Value('f1'),
              content: Value(
                doc([
                  {'insert': 'Intro'},
                  {
                    'insert': '\n',
                    'attributes': {'header': 1},
                  },
                  {'insert': 'See '},
                  {
                    'insert': 'Other',
                    'attributes': {'link': noteLink('n-other')},
                  },
                  {'insert': ' and '},
                  {
                    'insert': 'marked',
                    'attributes': {'background': hi},
                  },
                  {'insert': ' and '},
                  {
                    'insert': 'strong',
                    'attributes': {'bold': true},
                  },
                  {
                    'insert': ' per [@vaswani2017] with a note^[a footnote [@vaswani2017]].\n',
                  },
                  {'insert': 'first'},
                  {
                    'insert': '\n',
                    'attributes': {'list': 'bullet'},
                  },
                  {'insert': 'second'},
                  {
                    'insert': '\n',
                    'attributes': {'list': 'bullet', 'indent': 1},
                  },
                  {
                    'insert': {
                      'table': NoteTable(
                        rows: [
                          ['A', 'B'],
                          ['1', '2'],
                        ],
                      ).encode(),
                    },
                  },
                  {'insert': '\n'},
                  {'insert': r'$$ x^2 $$'},
                  {'insert': '\n'},
                  {'insert': 'a quote'},
                  {
                    'insert': '\n',
                    'attributes': {'blockquote': true},
                  },
                  {'insert': 'code line'},
                  {
                    'insert': '\n',
                    'attributes': {'code-block': true},
                  },
                ]),
              ),
            ),
          );
      await src
          .into(src.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n-other'),
              title: const Value('Other'),
              content: Value(
                doc([
                  {'insert': 'back to '},
                  {
                    'insert': 'Main: ideas',
                    'attributes': {'link': noteLink('n-main')},
                  },
                  {'insert': '\n'},
                ]),
              ),
            ),
          );
      await src
          .into(src.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: 'n-main', tagId: 't1'));
      await src
          .into(src.attachments)
          .insert(
            AttachmentsCompanion.insert(
              noteId: const Value('n-main'),
              type: AttachmentType.image,
              path: Value(pic.path),
              title: const Value('photo.png'),
            ),
          );

      final zip = await writeVaultZip(src, outDir: tmp);
      final files = loadVaultArchive(
        ZipDecoder().decodeBytes(zip.readAsBytesSync()),
      );
      final s = await importMarkdown(db, files);

      // Notes only: the paper page is skipped.
      expect(s.notes, 2);
      expect(s.skipped, 1);
      expect(s.unresolved, 0);
      expect(s.attachments, 1);

      final main = await _note(db, 'Main: ideas');
      final other = await _note(db, 'Other');
      final folder = await db.select(db.folders).getSingle();
      expect(folder.name, 'Reading');
      expect(main.folderId, folder.id);
      expect(other.folderId, isNull);

      final tagged = await db.select(db.noteTags).get();
      expect(tagged.single.noteId, main.id);

      expect(_links(main).single, ('Other', noteLink(other.id)));
      expect(_links(other).single, ('Main: ideas', noteLink(main.id)));

      final text = decodeNoteContent(main.content).toPlainText();
      expect(text, contains('[@vaswani2017]'));
      expect(text, contains('^[a footnote [@vaswani2017]]'));
      expect(text, contains(r'$$ x^2 $$'));
      expect(text, contains('a quote'));

      final ops = _ops(main);
      expect(
        ops.any(
          (o) =>
              o['insert'] == 'marked' &&
              (o['attributes'] as Map)['background'] == hi,
        ),
        isTrue,
      );
      expect(
        ops.any(
          (o) =>
              o['insert'] == 'strong' &&
              (o['attributes'] as Map)['bold'] == true,
        ),
        isTrue,
      );
      expect(
        ops.any(
          (o) =>
              o['insert'] == '\n' && (o['attributes'] as Map?)?['header'] == 1,
        ),
        isTrue,
      );
      expect(
        ops.where(
          (o) =>
              o['insert'] == '\n' &&
              (o['attributes'] as Map?)?['list'] == 'bullet',
        ),
        hasLength(2),
      );
      // (The exporter writes nested list items flat, so no indent here.)
      final table = ops.firstWhere(
        (o) => o['insert'] is Map && (o['insert'] as Map).containsKey('table'),
      );
      expect(
        NoteTable.decode((table['insert'] as Map)['table'] as String).rows,
        [
          ['A', 'B'],
          ['1', '2'],
        ],
      );
      expect(
        ops.any(
          (o) =>
              o['insert'] == '\n' &&
              (o['attributes'] as Map?)?['code-block'] == true,
        ),
        isTrue,
      );
      final atts = await db.select(db.attachments).get();
      expect(atts.single.type, AttachmentType.image);
      expect(atts.single.noteId, main.id);
    });

    test(
      'Obsidian-format text for heading, block and embed links, checklists',
      () async {
        await importMarkdown(db, [
          _text('Target.md', '## Section\n\nA paragraph. ^p1\n'),
          _text(
            'Source.md',
            '[[Target#Section]] [[Target#^p1]]\n\n![[Target]]\n![[Target#Section]]\n![[Target#^p1]]\n\n- [ ] open\n- [x] shut\n',
          ),
        ]);
        final target = await _note(db, 'Target');
        final source = await _note(db, 'Source');
        expect(_links(source), [
          ('Target › Section', noteLink(target.id, heading: 'Section')),
          ('Target › A paragraph.', noteLink(target.id, block: 'p1')),
        ]);
        final embeds = [
          for (final op in _ops(source))
            if (op['insert'] is Map)
              noteEmbedLink((op['insert'] as Map)[noteEmbedType] as String),
        ];
        expect(embeds, [
          noteLink(target.id),
          noteLink(target.id, heading: 'Section'),
          noteLink(target.id, block: 'p1'),
        ]);
        // The target keeps its block id as text.
        expect(
          decodeNoteContent(target.content).toPlainText(),
          contains(' ^p1'),
        );
        expect(
          _ops(source)
              .where((o) => (o['attributes'] as Map?)?['list'] != null)
              .length,
          2,
        );
      },
    );
  });
}
