import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/sync/sync_engine.dart';
import 'package:corplex/features/sync/sync_remote.dart';

import '../../support/fake_sync_remote.dart';

/// Two "devices" (separate local databases) syncing through one fake server.
void main() {
  late FakeSyncRemote server;
  late AppDatabase a;
  late AppDatabase b;
  late SyncEngine syncA;
  late SyncEngine syncB;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    server = FakeSyncRemote();
    a = AppDatabase.inMemoryForTesting();
    b = AppDatabase.inMemoryForTesting();
    syncA = SyncEngine(a, server);
    syncB = SyncEngine(b, server);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<void> both() async {
    await syncA.sync(userId: 'u1');
    await syncB.sync(userId: 'u1');
  }

  Future<int> tombstones(AppDatabase db) async =>
      (await db
              .customSelect('SELECT COUNT(*) AS c FROM sync_tombstones')
              .getSingle())
          .read<int>('c');

  test('a whole library created on one device appears on the other', () async {
    await a
        .into(a.folders)
        .insert(FoldersCompanion.insert(id: const Value('f1'), name: 'Thesis'));
    await a
        .into(a.tags)
        .insert(TagsCompanion.insert(id: const Value('t1'), name: 'ml'));
    await a
        .into(a.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention Is All You Need',
            authors: const Value('Vaswani'),
            year: const Value(2017),
            pdfPath: const Value('/device/a/only.pdf'),
          ),
        );
    await a
        .into(a.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Reading notes'),
            folderId: const Value('f1'),
          ),
        );
    await a
        .into(a.noteTags)
        .insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1'));
    await a
        .into(a.notePaperRefs)
        .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
    await a
        .into(a.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: const Value('at1'),
            paperId: const Value('p1'),
            type: AttachmentType.podcast,
            url: const Value('https://notebooklm.google.com/x'),
          ),
        );
    await a
        .into(a.annotations)
        .insert(
          AnnotationsCompanion.insert(
            id: const Value('an1'),
            paperId: 'p1',
            pageNumber: 3,
            pointsJson: '[[0.1,0.2]]',
          ),
        );

    await a
        .into(a.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: const Value('h1'),
            paperId: 'p1',
            pageNumber: 2,
            quote: 'Attention is all you need',
            rectsJson: '[[0.1,0.2,0.9,0.22]]',
          ),
        );
    await (a.update(a.papers)..where((p) => p.id.equals('p1'))).write(
      const PapersCompanion(
        lastPage: Value(7),
        readingStatus: Value(ReadingStatus.reading),
      ),
    );

    await both();

    expect(
      (await b.select(b.highlights).getSingle()).quote,
      'Attention is all you need',
    );
    final paper = await b.select(b.papers).getSingle();
    expect(paper.lastPage, 7);
    expect(paper.readingStatus, ReadingStatus.reading);
    expect(paper.title, 'Attention Is All You Need');
    expect(paper.year, 2017);
    expect(paper.pdfPath, isNull, reason: 'device-local paths never sync');
    expect((await b.select(b.notes).getSingle()).folderId, 'f1');
    expect(await b.select(b.noteTags).get(), hasLength(1));
    expect(await b.select(b.notePaperRefs).get(), hasLength(1));
    expect(
      (await b.select(b.attachments).getSingle()).url,
      contains('notebooklm'),
    );
    expect(
      (await b.select(b.annotations).getSingle()).pointsJson,
      '[[0.1,0.2]]',
    );
    expect(await tombstones(b), 0);
  });

  test('pulling does not overwrite this device\'s local file paths', () async {
    await a
        .into(a.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'T'));
    await both();
    await (b.update(b.papers)..where((p) => p.id.equals('p1'))).write(
      const PapersCompanion(pdfPath: Value('/device/b/copy.pdf')),
    );

    await (a.update(a.papers)..where((p) => p.id.equals('p1'))).write(
      PapersCompanion(
        title: const Value('Renamed'),
        updatedAt: Value(DateTime.utc(2031)),
      ),
    );
    await both();

    final paper = await b.select(b.papers).getSingle();
    expect(paper.title, 'Renamed');
    expect(paper.pdfPath, '/device/b/copy.pdf');
  });

  test('projects and their memberships sync, including removals', () async {
    await a
        .into(a.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'T'));
    await a.into(a.notes).insert(NotesCompanion.insert(id: const Value('n1')));
    await a
        .into(a.projects)
        .insert(
          ProjectsCompanion.insert(id: const Value('pr1'), name: 'Review'),
        );
    await a
        .into(a.projectPapers)
        .insert(ProjectPapersCompanion.insert(projectId: 'pr1', paperId: 'p1'));
    await a
        .into(a.projectNotes)
        .insert(ProjectNotesCompanion.insert(projectId: 'pr1', noteId: 'n1'));

    await both();

    expect((await b.select(b.projects).getSingle()).name, 'Review');
    expect(await b.select(b.projectPapers).get(), hasLength(1));
    expect(await b.select(b.projectNotes).get(), hasLength(1));

    await a.delete(a.projectPapers).go();
    await both();
    expect(await b.select(b.projectPapers).get(), isEmpty);
    expect(await b.select(b.projectNotes).get(), hasLength(1));
    expect(await b.select(b.papers).get(), hasLength(1));
  });

  test('edits propagate', () async {
    await a
        .into(a.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('v1'),
          ),
        );
    await both();

    await (a.update(a.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(
        title: const Value('v2'),
        updatedAt: Value(DateTime.utc(2031)),
      ),
    );
    await both();

    expect((await b.select(b.notes).getSingle()).title, 'v2');
  });

  test(
    'deleting a note removes it, its links and attachments elsewhere',
    () async {
      await a
          .into(a.notes)
          .insert(NotesCompanion.insert(id: const Value('n1')));
      await a
          .into(a.papers)
          .insert(
            PapersCompanion.insert(id: const Value('p1'), title: 'Keep me'),
          );
      await a
          .into(a.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: 'n1', paperId: 'p1'));
      await a
          .into(a.attachments)
          .insert(
            AttachmentsCompanion.insert(
              noteId: const Value('n1'),
              type: AttachmentType.link,
              url: const Value('https://x.test'),
            ),
          );
      await both();
      expect(await b.select(b.notes).get(), hasLength(1));

      await (a.delete(a.notes)..where((n) => n.id.equals('n1'))).go();
      await both();

      expect(await b.select(b.notes).get(), isEmpty);
      expect(await b.select(b.notePaperRefs).get(), isEmpty);
      expect(await b.select(b.attachments).get(), isEmpty);
      expect(await b.select(b.papers).get(), hasLength(1));
      expect(await tombstones(b), 0, reason: 'applying a delete must not echo');
      expect(await tombstones(a), 0, reason: 'tombstones clear once pushed');
    },
  );

  test(
    'unlinking then re-linking a join row ends up linked everywhere',
    () async {
      await a
          .into(a.notes)
          .insert(NotesCompanion.insert(id: const Value('n1')));
      await a
          .into(a.tags)
          .insert(TagsCompanion.insert(id: const Value('t1'), name: 'x'));
      await a
          .into(a.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: 'n1', tagId: 't1'));
      await both();

      await a.delete(a.noteTags).go();
      await both();
      expect(await b.select(b.noteTags).get(), isEmpty);

      await a
          .into(a.noteTags)
          .insert(
            NoteTagsCompanion.insert(
              noteId: 'n1',
              tagId: 't1',
              updatedAt: Value(DateTime.utc(2031)),
            ),
          );
      await both();
      expect(await b.select(b.noteTags).get(), hasLength(1));
    },
  );

  test(
    'last write wins: a stale offline edit does not clobber a newer one',
    () async {
      await a
          .into(a.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('base'),
            ),
          );
      await both();

      // B edits later than A, and syncs first.
      await (b.update(b.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          title: const Value('from B'),
          updatedAt: Value(DateTime.utc(2031, 1, 2)),
        ),
      );
      await (a.update(a.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          title: const Value('from A'),
          updatedAt: Value(DateTime.utc(2031, 1, 1)),
        ),
      );
      await syncB.sync(userId: 'u1');
      await syncA.sync(userId: 'u1');
      await syncB.sync(userId: 'u1');

      expect((await a.select(a.notes).getSingle()).title, 'from B');
      expect((await b.select(b.notes).getSingle()).title, 'from B');
    },
  );

  group('the same row edited on two devices between syncs', () {
    String body(List<String> paragraphs) => jsonEncode([
      for (final p in paragraphs) {'insert': '$p\n'},
    ]);
    List<String> paragraphs(Note n) {
      final text = decodeNoteContent(n.content).toPlainText();
      return text.substring(0, text.length - 1).split('\n');
    }

    Future<void> edit(AppDatabase db, NotesCompanion change) =>
        (db.update(db.notes)..where((n) => n.id.equals('n1'))).write(change);

    Future<int> bases(AppDatabase db) async =>
        (await db
                .customSelect('SELECT COUNT(*) AS c FROM sync_base')
                .getSingle())
            .read<int>('c');

    setUp(() async {
      await a
          .into(a.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Review'),
              content: Value(body(['Intro', 'Method', 'Findings'])),
            ),
          );
      await both();
    });

    test('edits to different paragraphs are both kept', () async {
      await edit(
        a,
        NotesCompanion(
          content: Value(body(['Intro, sharpened', 'Method', 'Findings'])),
        ),
      );
      await edit(
        b,
        NotesCompanion(
          content: Value(body(['Intro', 'Method', 'Findings', 'Critique'])),
        ),
      );
      await syncA.sync(userId: 'u1');
      await syncB.sync(userId: 'u1');
      await syncA.sync(userId: 'u1');

      const expected = ['Intro, sharpened', 'Method', 'Findings', 'Critique'];
      expect(paragraphs(await b.select(b.notes).getSingle()), expected);
      expect(paragraphs(await a.select(a.notes).getSingle()), expected);
      expect(await bases(a), 0, reason: 'bases go once pushed');
      expect(await bases(b), 0);
    });

    test('a title changed here and a body changed there', () async {
      await edit(a, const NotesCompanion(title: Value('Literature review')));
      await edit(
        b,
        NotesCompanion(
          content: Value(body(['Intro', 'Method', 'Findings', 'Gaps'])),
        ),
      );
      await syncB.sync(userId: 'u1');
      await syncA.sync(userId: 'u1');
      await syncB.sync(userId: 'u1');

      for (final db in [a, b]) {
        final note = await db.select(db.notes).getSingle();
        expect(note.title, 'Literature review');
        expect(paragraphs(note), ['Intro', 'Method', 'Findings', 'Gaps']);
      }
    });

    test('the same paragraph rewritten on both keeps both wordings', () async {
      await edit(
        a,
        NotesCompanion(content: Value(body(['Intro', 'Method A', 'Findings']))),
      );
      await edit(
        b,
        NotesCompanion(content: Value(body(['Intro', 'Method B', 'Findings']))),
      );
      await syncA.sync(userId: 'u1');
      await syncB.sync(userId: 'u1');
      await syncA.sync(userId: 'u1');

      expect(paragraphs(await a.select(a.notes).getSingle()), [
        'Intro',
        'Method B',
        'Method A',
        'Findings',
      ]);
    });

    test('a later edit after syncing is not merged again', () async {
      await edit(a, NotesCompanion(content: Value(body(['Only A']))));
      await both();
      await edit(b, NotesCompanion(content: Value(body(['Then B']))));
      await both();
      await syncA.sync(userId: 'u1');
      for (final db in [a, b]) {
        expect(paragraphs(await db.select(db.notes).getSingle()), ['Then B']);
      }
    });

    test('paper fields edited on each device both land', () async {
      await a
          .into(a.papers)
          .insert(PapersCompanion.insert(id: const Value('p1'), title: 'T'));
      await both();
      await (a.update(a.papers)..where((p) => p.id.equals('p1'))).write(
        const PapersCompanion(rating: Value(5)),
      );
      await (b.update(b.papers)..where((p) => p.id.equals('p1'))).write(
        const PapersCompanion(venue: Value('NeurIPS')),
      );
      await syncA.sync(userId: 'u1');
      await syncB.sync(userId: 'u1');
      await syncA.sync(userId: 'u1');
      for (final db in [a, b]) {
        final paper = await db.select(db.papers).getSingle();
        expect((paper.rating, paper.venue), (5, 'NeurIPS'));
      }
    });
  });

  test('a newer local edit survives a pull of an older remote delete', () async {
    await a.into(a.notes).insert(NotesCompanion.insert(id: const Value('n1')));
    await both();

    await (a.delete(a.notes)..where((n) => n.id.equals('n1'))).go();
    await syncA.sync(userId: 'u1');
    // B edits after the delete happened (its edit is newer than the tombstone).
    await (b.update(b.notes)..where((n) => n.id.equals('n1'))).write(
      NotesCompanion(
        title: const Value('kept'),
        updatedAt: Value(DateTime.utc(2099)),
      ),
    );
    await both();
    await syncA.sync(userId: 'u1');

    expect((await a.select(a.notes).getSingle()).title, 'kept');
  });

  test('a second sync with no changes is a no-op', () async {
    await a.into(a.folders).insert(FoldersCompanion.insert(name: 'F'));
    await both();
    final before = Map.of(server.tables['folders']!.values.single);

    await both();

    expect(
      server.tables['folders']!.values.single['synced_at'],
      before['synced_at'],
      reason: 'unchanged rows are not re-pushed after the first round',
    );
  });

  test('a device signed in to another account refuses to sync', () async {
    await a.into(a.folders).insert(FoldersCompanion.insert(name: 'F'));
    await syncA.sync(userId: 'u1');

    expect(() => syncA.sync(userId: 'u2'), throwsA(isA<SyncAccountMismatch>()));
  });

  test('data created while signed out uploads on first sign-in', () async {
    await a
        .into(a.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('offline'),
          ),
        );

    await both();

    expect((await b.select(b.notes).getSingle()).title, 'offline');
  });

  test(
    'the pull cursor advances to the newest change, whatever the order',
    () async {
      server.newestFirst = true;
      Future<String> notesCursor(AppDatabase db) async =>
          (await db.customSelect('SELECT last_pull FROM sync_meta').getSingle())
              .read<String>('last_pull');

      await a
          .into(a.notes)
          .insert(NotesCompanion.insert(id: const Value('n1')));
      await a
          .into(a.notes)
          .insert(NotesCompanion.insert(id: const Value('n2')));
      await both();
      final newest = server.tables['notes']!.values
          .map((r) => r['synced_at']! as String)
          .reduce((x, y) => x.compareTo(y) > 0 ? x : y);
      expect(await notesCursor(b), contains(newest));

      // A later change moves it forward again.
      await (a.update(a.notes)..where((n) => n.id.equals('n1'))).write(
        NotesCompanion(
          title: const Value('edited'),
          updatedAt: Value(DateTime.utc(2031)),
        ),
      );
      await both();
      final edited = server.tables['notes']!['n1']!['synced_at']! as String;
      expect(await notesCursor(b), contains(edited));
      expect(
        (await (b.select(
          b.notes,
        )..where((n) => n.id.equals('n1'))).getSingle()).title,
        'edited',
      );
    },
  );

  test('an un-migrated table is skipped, not fatal: the rest syncs and its changes wait', () async {
    server.missingTables.addAll({'projects', 'project_papers', 'highlights'});
    await a
        .into(a.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('syncs fine'),
          ),
        );
    await a
        .into(a.papers)
        .insert(PapersCompanion.insert(id: const Value('p1'), title: 'P'));
    await a
        .into(a.projects)
        .insert(
          ProjectsCompanion.insert(id: const Value('pr'), name: 'Waiting'),
        );

    // Reported, but everything the server does have went through.
    await expectLater(
      syncA.sync(userId: 'u1'),
      throwsA(isA<SyncServerOutdated>()),
    );
    await expectLater(
      syncB.sync(userId: 'u1'),
      throwsA(isA<SyncServerOutdated>()),
    );
    expect((await b.select(b.notes).getSingle()).title, 'syncs fine');
    expect(await b.select(b.papers).get(), hasLength(1));
    expect(await b.select(b.projects).get(), isEmpty);
    expect(
      await syncA.pendingChanges(),
      1,
      reason: 'the project change is still queued',
    );

    // Once the server is migrated, the waiting change goes up.
    server.missingTables.clear();
    await both();
    expect((await b.select(b.projects).getSingle()).name, 'Waiting');
    expect(await syncA.pendingChanges(), 0);
  });
}
