import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/search/search_index.dart';

String _doc(String text) => '[{"insert":"$text\\n"}]';

Future<void> _note(
  AppDatabase db,
  String id,
  String title,
  String body, {
  String? folderId,
  String? aliases,
  bool pinned = false,
  bool template = false,
  String? daily,
}) => db
    .into(db.notes)
    .insert(
      NotesCompanion.insert(
        id: Value(id),
        title: Value(title),
        content: Value(_doc(body)),
        folderId: Value(folderId),
        aliases: Value(aliases),
        pinned: Value(pinned),
        isTemplate: Value(template),
        dailyDate: Value(daily),
      ),
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(id: const Value('f1'), name: 'Lab'));
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(id: const Value('f2'), name: 'Lab / Notes'),
        );
    await _note(
      db,
      'n1',
      'Cortex notes',
      'Neurons fire in the cortex',
      folderId: 'f1',
      pinned: true,
    );
    await _note(
      db,
      'n2',
      'Cortex reading',
      'Cortex layers and noise',
      folderId: 'f2',
      aliases: 'Neocortex; Pallium',
    );
    await _note(db, 'n3', 'Weekly template', 'Cortex agenda', template: true);
    await _note(
      db,
      'n4',
      'Tuesday',
      'Cortex daily thoughts',
      daily: '2026-10-20',
    );
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(id: const Value('t1'), name: 'Deep Learning'),
        );
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t2'), name: 'ml'));
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t3'), name: 'ml/vision'));
    for (final (n, t) in [('n1', 't1'), ('n2', 't2'), ('n4', 't3')]) {
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: n, tagId: t));
    }
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Cortex dynamics',
            authors: const Value('Doe, Jane'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p2'),
            title: 'Cortex and sleep',
            authors: const Value('Roe, Rick'),
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: const Value('h1'),
            paperId: 'p1',
            pageNumber: 2,
            quote: 'the cortex is layered',
            rectsJson: '[]',
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: const Value('h2'),
            paperId: 'p2',
            pageNumber: 5,
            quote: 'cortex during sleep',
            rectsJson: '[]',
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(id: const Value('pr'), name: 'Thesis'),
        );
    await db
        .into(db.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr', paperId: 'p1'));
    await db
        .into(db.projectNotes)
        .insert(ProjectNotesCompanion.insert(projectId: 'pr', noteId: 'n2'));
  });
  tearDown(() => db.close());

  // Run every operator test against FTS and against the substring fallback.
  for (final fts in [true, false]) {
    group(fts ? 'with FTS5' : 'without FTS5', () {
      late SearchIndex index;
      setUp(() => index = SearchIndex(db, useFts: fts));
      tearDown(() => index.dispose());

      Future<Set<String>> ids(String q) async => {
        for (final h in await index.search(q)) '${h.kind.name}:${h.id}',
      };

      test('availability matches the mode', () async {
        expect(await index.available, fts);
      });

      test('plain words still work', () async {
        expect(await ids('cortex'), containsAll(['note:n1', 'paper:p1']));
        expect(await ids('layers noise'), {'note:n2'});
      });

      test('in: restricts kinds', () async {
        expect(await ids('cortex in:papers'), {'paper:p1', 'paper:p2'});
        expect(await ids('cortex in:highlights'), {
          'highlight:h1',
          'highlight:h2',
        });
        expect(
          (await ids('cortex in:notes')).every((e) => e.startsWith('note:')),
          isTrue,
        );
        expect(
          (await ids('cortex -in:notes')).any((e) => e.startsWith('note:')),
          isFalse,
        );
      });

      test('negative words and phrases', () async {
        expect(await ids('cortex in:notes -noise'), isNot(contains('note:n2')));
        expect(await ids('cortex in:notes -noise'), contains('note:n1'));
        expect(await ids('"cortex layers" in:notes'), {'note:n2'});
        expect(await ids('"layers cortex" in:notes'), isEmpty);
      });

      test('negative-only queries scan', () async {
        final found = await ids('-noise in:notes');
        expect(found, {'note:n1', 'note:n3', 'note:n4'});
      });

      test('tag:, quoted, nested and negated', () async {
        expect(await ids('cortex tag:"deep learning" in:notes'), {'note:n1'});
        // ml also matches the nested ml/vision.
        expect(await ids('cortex tag:ml in:notes'), {'note:n2', 'note:n4'});
        expect(await ids('tag:#ml/vision'), {'note:n4'});
        expect(await ids('cortex -tag:ml in:notes'), {'note:n1', 'note:n3'});
        // Papers have no tags: a positive tag leaves them out.
        expect(
          (await ids('cortex tag:ml')).any((e) => !e.startsWith('note:')),
          isFalse,
        );
      });

      test('folder: / path: includes sub-folders', () async {
        expect(await ids('cortex folder:lab in:notes'), {'note:n1', 'note:n2'});
        expect(await ids('cortex path:"Lab / Notes" in:notes'), {'note:n2'});
        expect(await ids('folder:lab -folder:"lab / notes"'), {'note:n1'});
      });

      test('project: filters notes, papers and highlights', () async {
        expect(await ids('cortex project:thesis'), {
          'note:n2',
          'paper:p1',
          'highlight:h1',
        });
        expect(await ids('cortex -project:thesis in:papers'), {'paper:p2'});
      });

      test('is:pinned / template / daily', () async {
        expect(await ids('cortex is:pinned'), {'note:n1'});
        expect(await ids('cortex is:template'), {'note:n3'});
        expect(await ids('cortex is:daily'), {'note:n4'});
        expect(await ids('cortex -is:pinned in:notes'), {
          'note:n2',
          'note:n3',
          'note:n4',
        });
        expect(await ids('is:pinned'), {'note:n1'});
      });

      test('aliases find the note', () async {
        expect(await ids('neocortex'), {'note:n2'});
        expect(await ids('pallium in:notes'), {'note:n2'});
        expect(await ids('pallium'), {'note:n2'});
      });

      test('hostile input never throws', () async {
        for (final q in [
          '"',
          '-',
          'NOT',
          '*',
          '^',
          '(a',
          'a)',
          'x" y',
          'a -',
        ]) {
          await index.search(q);
        }
      });
    });
  }

  group('aliases in the index', () {
    test('a hit by alias shows the alias, a hit by title does not', () async {
      final index = SearchIndex(db);
      addTearDown(index.dispose);
      final byAlias = (await index.search('pallium')).single;
      expect(byAlias.title, contains('Cortex reading'));
      expect(byAlias.title, contains('⟦Pallium⟧'));
      final byTitle = (await index.search('reading')).single;
      expect(byTitle.title, 'Cortex ⟦reading⟧');
      expect(byTitle.title, isNot(contains('Pallium')));
    });

    test('editing aliases re-indexes the note', () async {
      final index = SearchIndex(db);
      addTearDown(index.dispose);
      expect(await index.search('hippocampus'), isEmpty);
      await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          aliases: const Value('Hippocampus'),
          updatedAt: Value(DateTime.now().add(const Duration(seconds: 5))),
        ),
      );
      expect((await index.search('hippocampus')).single.id, 'n1');
      await (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          aliases: const Value(null),
          updatedAt: Value(DateTime.now().add(const Duration(seconds: 10))),
        ),
      );
      expect(await index.search('hippocampus'), isEmpty);
    });

    test('locked notes are still found by title and alias only', () async {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('lk'),
              title: const Value('Secret plans'),
              aliases: const Value('Hush'),
              content: const Value('corplex-locked:v1:k:AAAA'),
            ),
          );
      final index = SearchIndex(db);
      addTearDown(index.dispose);
      final hit = (await index.search('hush')).single;
      expect(hit.locked, isTrue);
      expect(hit.snippet, 'Locked');
    });
  });
}
