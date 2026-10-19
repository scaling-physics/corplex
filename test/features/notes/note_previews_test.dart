import 'package:corplex/data/database.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/notes_providers.dart';
import 'package:drift/drift.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

String body(String text) => encodeNoteContent(Document()..insert(0, text));

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
  });
  tearDown(() => db.close());

  Future<void> addNote(
    String id, {
    String title = '',
    String text = '',
    String? folderId,
    DateTime? updated,
  }) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title),
          content: Value(text.isEmpty ? '' : body(text)),
          folderId: Value(folderId),
          updatedAt: updated == null ? const Value.absent() : Value(updated),
        ),
      );

  Future<List<NoteListItem>> list([NotesFilter f = const AllNotes()]) =>
      watchNoteList(db, f).first;

  Future<Map<String, String>> stored() async => {
    for (final r in await db.select(db.notePreviews).get())
      r.noteId: '${r.preview}|${r.locked}',
  };

  test('first load computes and stores the preview', () async {
    await addNote('a', title: 'A', text: 'Hello   world\nsecond line');
    expect(await stored(), isEmpty);
    final items = await list();
    expect(items.single.preview, 'Hello world second line');
    expect(items.single.locked, isFalse);
    expect(await stored(), {'a': 'Hello world second line|false'});
  });

  test('a content edit through drift refreshes the preview', () async {
    await addNote('a', text: 'one');
    await list();
    await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
      NotesCompanion(content: Value(body('two'))),
    );
    expect(await stored(), isEmpty); // trigger dropped it
    expect((await list()).single.preview, 'two');
  });

  test('a content edit through raw SQL (like sync) is caught too', () async {
    await addNote('a', text: 'one');
    await list();
    await db.customStatement('UPDATE notes SET content = ? WHERE id = ?', [
      body('synced'),
      'a',
    ]);
    expect(await stored(), isEmpty);
    expect((await list()).single.preview, 'synced');
    // INSERT OR REPLACE (a pulled row) as well.
    await db.customStatement(
      'INSERT OR REPLACE INTO notes (id, title, content, pinned, created_at, '
      'updated_at) VALUES (?, ?, ?, 0, 1, 2)',
      ['a', '', body('replaced')],
    );
    expect((await list()).single.preview, 'replaced');
  });

  test('a title-only edit keeps the stored preview', () async {
    await addNote('a', text: 'one');
    await list();
    // Plant a marker only a recompute would overwrite.
    await db.customStatement("UPDATE note_previews SET preview = 'kept'");
    await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
      const NotesCompanion(title: Value('New title')),
    );
    final items = await list();
    expect(items.single.title, 'New title');
    expect(items.single.preview, 'kept');
  });

  test('the preview goes with the note', () async {
    await addNote('a', text: 'one');
    await list();
    await (db.delete(db.notes)..where((n) => n.id.equals('a'))).go();
    expect(await stored(), isEmpty);
  });

  test('a locked note stores no plain text and lists as locked', () async {
    await addNote('a', title: 'Secret', text: 'top secret words');
    final service = NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );
    await service.setPassword('pw');
    await list(); // plain preview stored first
    await service.lockNote('a');
    expect(await stored(), isEmpty); // content changed, preview dropped
    final item = (await list()).single;
    expect(item.locked, isTrue);
    expect(item.preview, isEmpty);
    expect(await stored(), {'a': '|true'});
    final dump = (await db.select(db.notePreviews).get()).toString();
    expect(dump, isNot(contains('secret')));
  });

  test('long bodies are cut', () async {
    await addNote('a', text: 'word ' * 500);
    expect((await list()).single.preview.length, lessThanOrEqualTo(300));
  });

  test('filters and ordering still work', () async {
    final now = DateTime(2026, 10, 18, 12);
    await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(id: const Value('f'), name: 'F'));
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: const Value('t'), name: 'T'));
    await db
        .into(db.projects)
        .insert(ProjectsCompanion.insert(id: const Value('p'), name: 'P'));
    await addNote('old', updated: now.subtract(const Duration(days: 2)));
    await addNote('new', updated: now, folderId: 'f');
    await addNote('pin', updated: now.subtract(const Duration(days: 9)));
    await (db.update(db.notes)..where((n) => n.id.equals('pin'))).write(
      const NotesCompanion(pinned: Value(true)),
    );
    await db
        .into(db.noteTags)
        .insert(NoteTagsCompanion.insert(noteId: 'old', tagId: 't'));
    await db
        .into(db.projectNotes)
        .insert(ProjectNotesCompanion.insert(projectId: 'p', noteId: 'new'));

    List<String> ids(List<NoteListItem> l) => [for (final n in l) n.id];
    expect(ids(await list()), ['pin', 'new', 'old']);
    expect(ids(await list(const FolderFilter('f'))), ['new']);
    expect(ids(await list(const TagFilter('t'))), ['old']);
    expect(ids(await list(const ProjectFilter('p'))), ['new']);
  });

  test('no rebuild loop: filling emits once, then goes quiet', () async {
    for (var i = 0; i < 5; i++) {
      await addNote('n$i', text: 'text $i');
    }
    final emissions = <List<NoteListItem>>[];
    final sub = watchNoteList(db, const AllNotes()).listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(emissions, hasLength(1));
    expect(emissions.single.every((n) => n.preview.isNotEmpty), isTrue);
    // A title edit emits once more, without recomputing anything.
    await (db.update(db.notes)..where((n) => n.id.equals('n0'))).write(
      const NotesCompanion(title: Value('x')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(emissions, hasLength(2));
    await sub.cancel();
  });

  test('more stale rows than one pass are filled over several', () async {
    for (var i = 0; i < previewsPerPass + 10; i++) {
      await addNote('n$i', text: 'text $i');
    }
    final emissions = <List<NoteListItem>>[];
    final sub = watchNoteList(db, const AllNotes()).listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(emissions, hasLength(2));
    expect(emissions.last.every((n) => n.preview.isNotEmpty), isTrue);
    expect(
      await db.select(db.notePreviews).get(),
      hasLength(previewsPerPass + 10),
    );
    await sub.cancel();
  });
}
