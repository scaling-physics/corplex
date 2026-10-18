import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/search/search_index.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

String _body(String text) => '[{"insert":"$text\\n"}]';

Future<void> _addNote(AppDatabase db, String id, String title, String text) =>
    db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(_body(text)),
          ),
        );

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
        .read<int>('c');

void main() {
  late AppDatabase db;
  late SearchIndex index;

  setUp(() {
    db = AppDatabase.inMemoryForTesting();
    index = SearchIndex(db);
  });
  tearDown(() async {
    index.dispose();
    await db.close();
  });

  test('a warm refresh does not re-read unchanged rows', () async {
    await _addNote(db, 'a', 'Alpha', 'zebra stripes');
    await _addNote(db, 'b', 'Beta', 'quokka smiles');
    await index.refresh();
    // Change the index behind the data's back: a re-read would repair it.
    await db.customStatement(
      "UPDATE search_index SET body = 'tampered' WHERE ref = 'a'",
    );
    await index.refresh();
    final row = await db
        .customSelect("SELECT body FROM search_index WHERE ref = 'a'")
        .getSingle();
    expect(row.read<String>('body'), 'tampered');
  });

  test('only the edited row is re-indexed, and keeps one entry', () async {
    await _addNote(db, 'a', 'Alpha', 'zebra stripes');
    await _addNote(db, 'b', 'Beta', 'quokka smiles');
    await index.refresh();
    await db.customStatement(
      "UPDATE search_index SET body = 'tampered' WHERE ref = 'b'",
    );
    await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
      NotesCompanion(
        content: Value(_body('okapi grazes')),
        updatedAt: Value(DateTime.now().add(const Duration(seconds: 5))),
      ),
    );
    await index.refresh();
    expect((await index.search('okapi')).single.id, 'a');
    expect(await index.search('zebra'), isEmpty);
    // b was not re-read.
    final b = await db
        .customSelect("SELECT body FROM search_index WHERE ref = 'b'")
        .getSingle();
    expect(b.read<String>('body'), 'tampered');
    expect(await _count(db, 'search_state'), 2);
    expect(await _count(db, 'search_index'), 2);
  });

  test('deleted rows leave the index and the state', () async {
    await _addNote(db, 'a', 'Alpha', 'zebra');
    await index.refresh();
    await (db.delete(db.notes)..where((n) => n.id.equals('a'))).go();
    expect(await index.search('zebra'), isEmpty);
    expect(await _count(db, 'search_state'), 0);
    expect(await _count(db, 'search_index'), 0);
  });

  test(
    'a backup (no search_index) rebuilds instead of trusting state',
    () async {
      await _addNote(db, 'a', 'Alpha', 'zebra stripes');
      await index.refresh();
      // What backup.dart does to its copy.
      await db.customStatement('DROP TABLE search_index');
      final fresh = SearchIndex(db);
      addTearDown(fresh.dispose);
      expect((await fresh.search('zebra')).single.id, 'a');
    },
  );

  test(
    'an index from before search_state is rebuilt, not duplicated',
    () async {
      await _addNote(db, 'a', 'Alpha', 'zebra stripes');
      await index.refresh();
      await db.customStatement('DROP TABLE search_state');
      final fresh = SearchIndex(db);
      addTearDown(fresh.dispose);
      expect((await fresh.search('zebra')).length, 1);
      expect(await _count(db, 'search_index'), 1);
    },
  );

  test('simultaneous refreshes share work and end consistent', () async {
    await _addNote(db, 'a', 'Alpha', 'zebra');
    final first = index.refresh();
    await _addNote(db, 'b', 'Beta', 'quokka');
    await Future.wait([first, index.refresh(), index.refresh()]);
    expect((await index.search('quokka')).single.id, 'b');
    expect(await _count(db, 'search_index'), 2);
  });

  test('note previews are cached but follow the content', () {
    final a = _body('first words');
    expect(notePlainTextPreview(a), 'first words');
    expect(notePlainTextPreview(a), 'first words');
    expect(notePlainTextPreview(_body('other')), 'other');
    expect(notePlainTextPreview(''), '');
    expect(notePlainTextPreview('plain, not JSON'), 'plain, not JSON');
  });
}
