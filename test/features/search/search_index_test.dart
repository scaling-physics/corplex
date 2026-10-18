import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/search/search_index.dart';

const _quill =
    r'[{"insert":"Self-attention lets every position attend to every other.\n"}]';

void main() {
  late AppDatabase db;
  late SearchIndex index;

  setUp(() async {
    db = AppDatabase.inMemoryForTesting();
    index = SearchIndex(db);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Transformer notes'),
            content: const Value(_quill),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n2'),
            title: const Value('Grocery list'),
            content: const Value('[{"insert":"milk, eggs\\n"}]'),
          ),
        );
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani, Ashish; Shazeer, Noam'),
            venue: const Value('NeurIPS'),
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: const Value('h1'),
            paperId: 'p1',
            pageNumber: 4,
            quote: 'Multi-head attention allows the model to jointly attend',
            rectsJson: '[]',
            comment: const Value('key idea for my thesis'),
          ),
        );
  });
  tearDown(() => db.close());

  test('this SQLite build has FTS5', () async {
    expect(await index.available, isTrue);
  });

  test(
    'finds notes by body text, papers by author, highlights by comment',
    () async {
      final notes = await index.search('every position');
      expect(notes.single.kind, SearchKind.note);
      expect(notes.single.id, 'n1');

      final byAuthor = await index.search('shazeer');
      expect(byAuthor.single.kind, SearchKind.paper);

      final byComment = await index.search('thesis');
      expect(byComment.single.kind, SearchKind.highlight);
      expect(byComment.single.paperId, 'p1');
      expect(byComment.single.page, 4);
    },
  );

  test('words match as prefixes; all words must appear', () async {
    expect((await index.search('transf')).map((h) => h.id), contains('n1'));
    expect(await index.search('milk transformer'), isEmpty);
  });

  test(
    'ignores case and diacritics, and survives FTS syntax characters',
    () async {
      expect(await index.search('ATTENTION'), isNotEmpty);
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n3'),
              title: const Value('Café résumé'),
            ),
          );
      expect((await index.search('cafe resume')).single.id, 'n3');
      // Would be a syntax error if passed to MATCH verbatim.
      // Operators are just words (none of these notes contain "and"/"not"),
      // and must not raise an FTS syntax error.
      expect(await index.search('"attention" AND (NOT'), isEmpty);
      expect(await index.search('attention (specifically'), isEmpty);
      expect(await index.search('   '), isEmpty);
      expect(await index.search('***'), isEmpty);
    },
  );

  test('matches are marked in titles and snippets', () async {
    final hit = (await index.search('attention'))
        .firstWhere((h) => h.kind == SearchKind.note);
    expect(hit.snippet, contains('⟦attention⟧'));
    final parts = splitMarked('a ⟦b⟧ c ⟦d⟧');
    expect(parts.where((p) => p.match).map((p) => p.text), ['b', 'd']);
    expect(parts.map((p) => p.text).join(), 'a b c d');
  });

  test('the index follows edits, deletes and new rows', () async {
    await index.search('milk'); // builds the index

    await (db.update(db.notes)..where((n) => n.id.equals('n2'))).write(
      NotesCompanion(
        content: const Value('[{"insert":"oat milk only\\n"}]'),
        updatedAt: Value(DateTime.now().add(const Duration(hours: 1))),
      ),
    );
    expect((await index.search('oat')).single.id, 'n2');

    await (db.delete(db.notes)..where((n) => n.id.equals('n2'))).go();
    expect(await index.search('oat'), isEmpty);

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n4'),
            title: const Value('Brand new'),
          ),
        );
    expect((await index.search('brand')).single.id, 'n4');
  });

  test('a title match ranks above a body match', () async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('body'),
            title: const Value('Misc'),
            content: const Value('[{"insert":"mentions quantum once\\n"}]'),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('title'),
            title: const Value('Quantum'),
          ),
        );
    final hits = (await index.search('quantum'))
        .where((h) => h.kind == SearchKind.note);
    expect(hits.first.id, 'title');
  });

  test('finds papers by study details and re-indexes after an edit', () async {
    expect(await index.search('optogenetics'), isEmpty);
    await (db.update(db.papers)..where((p) => p.id.equals('p1'))).write(
      PapersCompanion(
        techniques: const Value('optogenetics; patch clamp'),
        brainRegions: const Value('CA1'),
        updatedAt: Value(DateTime.now().add(const Duration(seconds: 5))),
      ),
    );
    expect((await index.search('optogenetics')).single.id, 'p1');
    expect((await index.search('CA1')).single.kind, SearchKind.paper);
  });

  test('a paper is found by a word in its abstract', () async {
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p9'),
            title: 'Sleep and memory',
            abstract: const Value('Hippocampal replay consolidates engrams.'),
          ),
        );
    final hits = await index.search('engrams');
    expect(hits.map((h) => h.id), contains('p9'));
  });
}
