import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:corplex/data/backup.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/database_provider.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/export/export_model.dart';
import 'package:corplex/features/export/vault_export.dart';
import 'package:corplex/features/graph/graph_model.dart';
import 'package:corplex/features/library/quote_to_note.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:corplex/features/notes/note_versions.dart';
import 'package:corplex/features/projects/abbreviations.dart';
import 'package:corplex/features/projects/chapters.dart';
import 'package:corplex/features/projects/coverage.dart';
import 'package:corplex/features/projects/figures.dart';
import 'package:corplex/features/projects/projects_providers.dart';
import 'package:corplex/features/projects/todos.dart';
import 'package:corplex/features/search/search_index.dart';
import 'package:corplex/features/sync/merge.dart';

const _secret = 'zebrafish';

String _body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  late AppDatabase db;
  late NoteLockService lock;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    lock = NoteLockService(
      db,
      crypto: NoteCrypto(iterations: 1000),
      inlineKdf: true,
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        noteLockServiceProvider.overrideWith((ref) => lock),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> addNote(String id, String text, {String? title}) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: Value(id),
          title: Value(title ?? 'Title $id'),
          content: Value(_body(text)),
        ),
      );

  Future<Note> note(String id) =>
      (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

  /// Sets a password, locks [id], and leaves the notes locked again.
  Future<void> lockAndRelock(String id) async {
    if (!await lock.hasPassword()) await lock.setPassword('pw');
    await lock.lockNote(id);
    lock.lockNow();
  }

  Future<T> firstValue<T>(dynamic provider, bool Function(T) ready) async {
    final done = Completer<T>();
    final sub = container.listen<Object?>(provider, (_, next) {
      final v = (next as AsyncValue).value;
      if (v != null && ready(v as T) && !done.isCompleted) done.complete(v);
    }, fireImmediately: true);
    addTearDown(sub.close);
    return done.future.timeout(const Duration(seconds: 5));
  }

  group('sync merge', () {
    Map<String, Object?> row(String content, int at) => {
      'id': 'n1',
      'title': 'T',
      'content': content,
      'updated_at': at,
      'created_at': 1,
    };

    test('a locked body is never line-merged with plain text', () {
      const envelope = 'corplex-locked:v1:k1:AAAA';
      final base = row(_body('one\ntwo'), 10);
      final local = row(envelope, 30);
      final remote = row(_body('one\ntwo\nthree'), 20);
      final merged = mergeRow(
        table: 'notes',
        columns: ['id', 'title', 'content', 'updated_at', 'created_at'],
        base: base,
        local: local,
        remote: remote,
      );
      expect(merged['content'], envelope);

      final reversed = mergeRow(
        table: 'notes',
        columns: ['id', 'title', 'content', 'updated_at', 'created_at'],
        base: base,
        local: row(_body('one\ntwo\nthree'), 20),
        remote: row(envelope, 30),
      );
      expect(reversed['content'], envelope);
    });

    test('two different envelopes keep the later one whole; titles merge', () {
      const a = 'corplex-locked:v1:k1:AAAA';
      const b = 'corplex-locked:v1:k1:BBBB';
      final merged = mergeRow(
        table: 'notes',
        columns: ['id', 'title', 'content', 'updated_at', 'created_at'],
        base: row(a, 10),
        local: {...row(a, 30), 'title': 'Mine'},
        remote: row(b, 20),
      );
      expect(merged['content'], b);
      expect(merged['title'], 'Mine');
    });

    test('note_versions bodies are also kept whole', () {
      const envelope = 'corplex-locked:v1:k1:AAAA';
      final merged = mergeRow(
        table: 'note_versions',
        columns: ['id', 'content', 'updated_at', 'created_at'],
        base: {
          'id': 'v',
          'content': _body('x'),
          'updated_at': 1,
          'created_at': 1,
        },
        local: {
          'id': 'v',
          'content': envelope,
          'updated_at': 5,
          'created_at': 1,
        },
        remote: {
          'id': 'v',
          'content': _body('x\ny'),
          'updated_at': 4,
          'created_at': 1,
        },
      );
      expect(merged['content'], envelope);
    });
  });

  group('search', () {
    test('locking a note removes its old text from the index', () async {
      await addNote('n1', 'the $_secret study', title: 'Fish notes');
      final index = SearchIndex(db);
      expect((await index.search(_secret)).map((h) => h.id), ['n1']);

      await lock.setPassword('pw');
      await lock.lockNote('n1');
      expect(await index.search(_secret), isEmpty);
      expect(await index.search('corplex'), isEmpty);
      expect(await index.search('locked'), isEmpty);

      final byTitle = await index.search('Fish');
      expect(byTitle, hasLength(1));
      expect(byTitle.single.locked, isTrue);
      expect(byTitle.single.snippet, 'Locked');

      final dump = await db
          .customSelect('SELECT title, body FROM search_index')
          .get();
      expect(
        dump.map((r) => r.read<String>('body')).join(),
        isNot(contains(_secret)),
      );
      expect(
        dump.map((r) => r.read<String>('body')).join(),
        isNot(contains('corplex-locked')),
      );
    });

    test('unlocking the lock (removeLock) makes it searchable again', () async {
      await addNote('n1', 'the $_secret study');
      await lock.setPassword('pw');
      await lock.lockNote('n1');
      final index = SearchIndex(db);
      expect(await index.search(_secret), isEmpty);
      await lock.removeLock('n1');
      expect((await index.search(_secret)).single.locked, isFalse);
    });
  });

  group('map', () {
    test('a locked note is a node by title with no content edges', () async {
      await addNote('n1', 'plain', title: 'Target');
      await addNote('n2', 'see corplex://note/n1', title: 'Linker');
      await db
          .into(db.projects)
          .insert(ProjectsCompanion.insert(id: const Value('x'), name: 'X'));
      // n2 links to n1 through its stored text.
      await db.customStatement('UPDATE notes SET content = ? WHERE id = ?', [
        jsonEncode([
          {
            'insert': 'go',
            'attributes': {'link': 'corplex://note/n1'},
          },
          {'insert': '\n'},
        ]),
        'n2',
      ]);
      var graph = await buildGraph(db);
      expect(graph.edges, hasLength(1));

      await lockAndRelock('n2');
      graph = await buildGraph(db);
      expect(
        graph.nodes.map((n) => n.label),
        containsAll(['Target', 'Linker']),
      );
      expect(graph.edges, isEmpty);
    });
  });

  group('projects', () {
    Future<String> projectWith(List<String> ids) async {
      final id = await findOrCreateProject(db, 'Thesis');
      for (final n in ids) {
        await db
            .into(db.projectNotes)
            .insert(ProjectNotesCompanion.insert(projectId: id, noteId: n));
      }
      return id;
    }

    test('chapter words: counted while unlocked, "locked" otherwise', () async {
      await addNote('a', 'one two three');
      await addNote('b', 'four five six seven eight');
      final project = await projectWith(['a', 'b']);
      await lockAndRelock('b');

      var chapters = await firstValue<List<Chapter>>(
        projectChaptersProvider(project),
        (c) => c.length == 2,
      );
      expect(chapters.map((c) => c.locked), [false, true]);
      expect(chapters.map((c) => c.words), [3, 0]);

      await lock.unlock('pw');
      chapters = await firstValue<List<Chapter>>(
        projectChaptersProvider(project),
        (c) => c.every((x) => !x.locked),
      );
      expect(chapters.map((c) => c.words), [3, 5]);
    });

    test(
      'to-dos and abbreviations skip a locked chapter, use an unlocked one',
      () async {
        await addNote('a', 'TODO fix intro');
        await addNote(
          'b',
          'We studied the medial prefrontal cortex (mPFC). TODO cite more',
        );
        final project = await projectWith(['a', 'b']);
        await lockAndRelock('b');

        final query = ChapterQuery(project, ['a', 'b']);
        var todos = await firstValue<List<ChapterTodos>>(
          todosProvider(query),
          (_) => true,
        );
        expect(todos.map((t) => t.noteId), ['a']);
        var abbr = await firstValue<AbbreviationReport>(
          abbreviationsProvider(project),
          (_) => true,
        );
        expect(abbr.defined, isEmpty);

        await lock.unlock('pw');
        todos = await firstValue<List<ChapterTodos>>(
          todosProvider(query),
          (t) => t.length == 2,
        );
        expect(todos.map((t) => t.noteId), ['a', 'b']);
        abbr = await firstValue<AbbreviationReport>(
          abbreviationsProvider(project),
          (a) => a.defined.isNotEmpty,
        );
        expect(abbr.defined.single.sf, 'mPFC');
      },
    );

    test('coverage never reads an envelope', () async {
      await addNote('a', 'cites [@smith2020]');
      final project = await projectWith(['a']);
      await lockAndRelock('a');
      final cov = await firstValue<Coverage>(
        coverageProvider(ChapterQuery(project, ['a'])),
        (_) => true,
      );
      expect(cov.chapters.single.cited, isEmpty);
      expect(cov.unknownKeys, isEmpty);
    });

    test(
      'figure numbering includes an unlocked chapter, not a locked one',
      () async {
        await addNote('a', '{#fig:aaa} First');
        await addNote('b', '{#fig:bbb} Second');
        await projectWith(['a', 'b']);
        await lockAndRelock('a');

        var index = await figureIndexForNote(db, 'b', lock: lock);
        expect(index.entries.map((e) => e.label), ['bbb']);
        expect(index.find(FigureKind.figure, 'bbb')!.number, '2.1');

        await lock.unlock('pw');
        index = await figureIndexForNote(db, 'b', lock: lock);
        expect(index.entries.map((e) => e.label), ['aaa', 'bbb']);
      },
    );
  });

  group('exports', () {
    test(
      'a locked body that reaches the builder is exported as title only',
      () async {
        await addNote('a', 'the $_secret study');
        await lockAndRelock('a');
        final n = await note('a');
        final doc = await buildExportDoc(db, [
          ExportNote(n.title, n.content),
        ], title: 'T');
        final text = doc.blocks.map((b) => b.text).join('\n');
        expect(text, isNot(contains('corplex-locked')));
        expect(text, isNot(contains(_secret)));
      },
    );

    test('the vault writes a placeholder, even while unlocked', () async {
      await addNote('a', 'the $_secret study', title: 'Fish');
      await addNote('b', 'plain text stays', title: 'Open');
      await lock.setPassword('pw');
      await lock.lockNote('a');
      expect(lock.anyUnlocked, isTrue);
      expect(await anyLockedNotes(db), isTrue);

      final result = await buildVaultArchive(db);
      final all = StringBuffer();
      String? locked;
      for (final f in result.archive.files) {
        if (!f.isFile) continue;
        final text = utf8.decode(f.content as List<int>, allowMalformed: true);
        all.write(text);
        if (f.name.endsWith('Fish.md')) locked = text;
      }
      expect(all.toString(), isNot(contains(_secret)));
      expect(all.toString(), isNot(contains('corplex-locked')));
      expect(all.toString(), contains('plain text stays'));
      expect(locked, contains('locked: true'));
      expect(locked, contains(lockedNotePlaceholder));
    });
  });

  group('versions', () {
    test(
      'a version of a locked note is its envelope; words only when readable',
      () async {
        await addNote('a', 'the $_secret study');
        await lock.setPassword('pw');
        await lock.lockNote('a');
        await saveNoteVersion(db, 'a', label: 'v1');
        final v = await db.select(db.noteVersions).getSingle();
        expect(isLockedContent(v.content), isTrue);
        expect(v.content, isNot(contains(_secret)));

        final texts = await firstValue<Map<String, String>>(
          versionTextsProvider('a'),
          (m) => m.isNotEmpty,
        );
        expect(texts[v.id], contains(_secret));
        lock.lockNow();
        final locked = await firstValue<Map<String, String>>(
          versionTextsProvider('a'),
          (m) => m.isEmpty,
        );
        expect(locked, isEmpty);
      },
    );

    test('restore needs the note unlocked and writes an envelope', () async {
      await addNote('a', 'old $_secret');
      await lock.setPassword('pw');
      await lock.lockNote('a');
      await saveNoteVersion(db, 'a', label: 'old');
      final v = await db.select(db.noteVersions).getSingle();
      // Change the body (still locked).
      await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
        NotesCompanion(
          content: Value(await lock.encryptBody('a', _body('new text'))),
          updatedAt: Value(DateTime.now()),
        ),
      );
      lock.lockNow();
      await expectLater(
        restoreNoteVersion(db, v.id, lock: lock),
        throwsA(isA<NoteLockedException>()),
      );
      expect(await db.select(db.noteVersions).get(), hasLength(1));

      expect(await lock.unlock('pw'), isTrue);
      expect(await restoreNoteVersion(db, v.id, lock: lock), isTrue);
      final restored = await note('a');
      expect(isLockedContent(restored.content), isTrue);
      expect(restored.content, isNot(contains(_secret)));
      expect(
        await lock.decryptBody('a', restored.content),
        contains('old $_secret'),
      );
      // "Before restoring" holds the previous (encrypted) body.
      final versions = await db.select(db.noteVersions).get();
      expect(versions, hasLength(2));
      expect(versions.every((x) => isLockedContent(x.content)), isTrue);
    });
  });

  group('quote to note', () {
    Future<(Highlight, Paper)> seed() async {
      await db
          .into(db.papers)
          .insert(PapersCompanion.insert(id: const Value('p'), title: 'Paper'));
      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              id: const Value('h'),
              paperId: 'p',
              pageNumber: 3,
              quote: 'a quoted passage',
              rectsJson: '[]',
            ),
          );
      return (
        await (db.select(
          db.highlights,
        )..where((h) => h.id.equals('h'))).getSingle(),
        await (db.select(
          db.papers,
        )..where((x) => x.id.equals('p'))).getSingle(),
      );
    }

    test(
      'a locked target is decrypted, appended to and re-encrypted',
      () async {
        await addNote('a', 'my $_secret');
        final (h, paper) = await seed();
        await lock.setPassword('pw');
        await lock.lockNote('a');

        lock.lockNow();
        await expectLater(
          quoteHighlightIntoNote(
            db,
            highlight: h,
            paper: paper,
            noteId: 'a',
            lock: lock,
          ),
          throwsA(isA<NoteLockedException>()),
        );
        expect(await db.select(db.notePaperRefs).get(), isEmpty);

        await lock.unlock('pw');
        await quoteHighlightIntoNote(
          db,
          highlight: h,
          paper: paper,
          noteId: 'a',
          lock: lock,
        );
        final after = await note('a');
        expect(isLockedContent(after.content), isTrue);
        final plain = await lock.decryptBody('a', after.content);
        expect(plain, contains('my $_secret'));
        expect(plain, contains('a quoted passage'));
      },
    );
  });

  group('trash and backup', () {
    test('trash and restore keep the envelope, still decryptable', () async {
      await addNote('a', 'my $_secret');
      await lock.setPassword('pw');
      await lock.lockNote('a');
      final before = (await note('a')).content;
      final id = await trashNote(db, 'a');
      final payload = (await db.select(db.trashItems).getSingle()).payloadJson;
      expect(payload, isNot(contains(_secret)));
      await restoreFromTrash(db, id);
      final after = await note('a');
      expect(after.content, before);
      expect(await lock.decryptBody('a', after.content), contains(_secret));
    });

    test('lockNote leaves no plain copy in sync_base', () async {
      await addNote('a', 'my $_secret');
      await db.customStatement('UPDATE notes SET content = ? WHERE id = ?', [
        _body('my $_secret edited'),
        'a',
      ]);
      await lock.setPassword('pw');
      final precondition = await db
          .customSelect('SELECT data FROM sync_base')
          .get();
      await lock.lockNote('a');
      final rows = await db.customSelect('SELECT data FROM sync_base').get();
      // (When the edit left a base, it held the plain text; now it's gone.)
      expect(precondition.length >= rows.length, isTrue);
      expect(
        rows.map((r) => r.read<String>('data')).join(),
        isNot(contains(_secret)),
      );
    });

    test(
      'a backup carries note_keys, so the restored notes still open',
      () async {
        final root = Directory.systemTemp.createTempSync('corplex_lock_backup');
        addTearDown(() => root.deleteSync(recursive: true));
        Directory dir(String n) =>
            Directory(p.join(root.path, n))..createSync(recursive: true);
        AppDatabase openIn(Directory docs) => AppDatabase.forTesting(
          NativeDatabase(
            File(p.join(docs.path, 'corplex.sqlite')),
            setup: (d) => d.execute('PRAGMA foreign_keys = ON;'),
          ),
        );

        final oldDocs = dir('old');
        final old = openIn(oldDocs);
        await old
            .into(old.notes)
            .insert(
              NotesCompanion.insert(
                id: const Value('a'),
                content: Value(_body('my $_secret')),
              ),
            );
        final oldLock = NoteLockService(
          old,
          crypto: NoteCrypto(iterations: 1000),
          inlineKdf: true,
        );
        await oldLock.setPassword('pw');
        await oldLock.lockNote('a');
        final zip = await createBackup(
          old,
          docsDir: oldDocs,
          outDir: dir('out'),
        );
        await old.close();

        final newDocs = dir('new');
        await stageRestore(
          zip,
          docsDir: newDocs,
          currentSchemaVersion: AppDatabase.inMemoryForTesting().schemaVersion,
        );
        expect(await applyPendingRestore(newDocs), isTrue);
        final restored = openIn(newDocs);
        addTearDown(restored.close);
        final fresh = NoteLockService(
          restored,
          crypto: NoteCrypto(iterations: 1000),
          inlineKdf: true,
        );
        final content =
            (await restored.select(restored.notes).getSingle()).content;
        expect(isLockedContent(content), isTrue);
        expect(fresh.canRead(content), isFalse);
        expect(await fresh.unlock('pw'), isTrue);
        expect(await fresh.decryptBody('a', content), contains(_secret));
      },
    );
  });
}
