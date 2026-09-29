@Tags(['integration'])
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, AuthFlowType, SupabaseClient;
import 'package:uuid/uuid.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/tables/papers_table.dart';
import 'package:corplex/features/auth/auth_service.dart';
import 'package:corplex/features/auth/supabase_auth_service.dart';
import 'package:corplex/features/sync/file_sync.dart';
import 'package:corplex/features/sync/sync_engine.dart';
import 'package:corplex/features/sync/sync_remote.dart';

/// Runs the real sync engine against a real Supabase stack. Skipped unless
/// pointed at one:
///
///   supabase start
///   flutter test test/integration --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=KEY_FROM_supabase_status
const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

class _Device {
  _Device(SupabaseClient client) {
    dir = Directory.systemTemp.createTempSync('corplex_it');
    db = AppDatabase.inMemoryForTesting();
    engine = SyncEngine(
      db,
      SupabaseSyncRemote(client),
      files: FileSync(db, SupabaseFileRemote(client), (sub, name) async {
        final d = Directory(p.join(dir.path, sub))..createSync(recursive: true);
        return p.join(d.path, name);
      }),
    );
  }

  late final Directory dir;
  late final AppDatabase db;
  late final SyncEngine engine;

  Future<void> dispose() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}

String _id() => const Uuid().v4();

void main() {
  final skip = (_url.isEmpty || _key.isEmpty)
      ? 'set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (see file header)'
      : null;

  late SupabaseClient client;
  late String userId;
  late _Device a;
  late _Device b;

  Future<(SupabaseClient, String)> newUser() async {
    final c = SupabaseClient(
      _url,
      _key,
      // Plain Dart has no storage for PKCE; the real app gets it from
      // Supabase.initialize.
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    final email = 'it_${DateTime.now().microsecondsSinceEpoch}@example.com';
    final auth = SupabaseAuthService(c.auth);
    await auth.signUp(email: email, password: 'password123');
    return (c, auth.currentUser!.id);
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    (client, userId) = await newUser();
    a = _Device(client);
    b = _Device(client);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('sign in / sign out round trip', () async {
    final auth = SupabaseAuthService(client.auth);
    final email = auth.currentUser!.email;
    await auth.signOut();
    expect(auth.currentUser, isNull);
    await expectLater(
      auth.signIn(email: email, password: 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
    await auth.signIn(email: email, password: 'password123');
    expect(auth.currentUser!.id, userId);
  }, skip: skip);

  test(
    'a full library, files included, syncs between two devices',
    () async {
      final folder = _id(), tag = _id(), paper = _id(), note = _id();
      final attach = _id(), podcast = _id(), stroke = _id();
      final pdf = File(p.join(a.dir.path, 'paper.pdf'))
        ..writeAsBytesSync(List.generate(5000, (i) => i % 251));
      final img = File(p.join(a.dir.path, 'shot.png'))
        ..writeAsBytesSync([1, 2, 3]);

      final db = a.db;
      await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(id: Value(folder), name: 'Thesis'));
      await db
          .into(db.tags)
          .insert(TagsCompanion.insert(id: Value(tag), name: 'ml'));
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(
              id: Value(paper),
              title: 'Attention Is All You Need',
              authors: const Value('Vaswani et al.'),
              year: const Value(2017),
              doi: const Value('10.5555/3295222.3295349'),
              pdfPath: Value(pdf.path),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(note),
              title: const Value('Reading notes'),
              content: const Value('[{"insert":"héllo ✓\\n"}]'),
              folderId: Value(folder),
            ),
          );
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: note, tagId: tag));
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: note, paperId: paper));
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: Value(attach),
              noteId: Value(note),
              type: AttachmentType.image,
              path: Value(img.path),
            ),
          );
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: Value(podcast),
              paperId: Value(paper),
              type: AttachmentType.podcast,
              url: const Value('https://notebooklm.google.com/notebook/abc'),
            ),
          );
      await db
          .into(db.annotations)
          .insert(
            AnnotationsCompanion.insert(
              id: Value(stroke),
              paperId: paper,
              pageNumber: 2,
              pointsJson: '[[0.1,0.2],[0.3,0.4]]',
            ),
          );

      await db
          .into(db.highlights)
          .insert(
            HighlightsCompanion.insert(
              paperId: paper,
              pageNumber: 4,
              quote: 'Multi-head attention',
              rectsJson: '[[0.1,0.2,0.8,0.22]]',
              comment: const Value('Key idea'),
            ),
          );
      await (db.update(db.papers)..where((p) => p.id.equals(paper))).write(
        const PapersCompanion(
          lastPage: Value(4),
          readingStatus: Value(ReadingStatus.reading),
        ),
      );

      final project = _id();
      await db
          .into(db.projects)
          .insert(ProjectsCompanion.insert(id: Value(project), name: 'Thesis'));
      await db
          .into(db.projectPapers)
          .insert(
            ProjectPapersCompanion.insert(projectId: project, paperId: paper),
          );
      await db
          .into(db.projectNotes)
          .insert(
            ProjectNotesCompanion.insert(projectId: project, noteId: note),
          );

      await a.engine.sync(userId: userId);
      await b.engine.sync(userId: userId);

      final bpr = await b.db.select(b.db.projects).getSingle();
      expect(bpr.name, 'Thesis');
      expect(await b.db.select(b.db.projectPapers).get(), hasLength(1));
      expect(await b.db.select(b.db.projectNotes).get(), hasLength(1));

      final bh = await b.db.select(b.db.highlights).getSingle();
      expect(bh.quote, 'Multi-head attention');
      expect(bh.comment, 'Key idea');
      final bp = await b.db.select(b.db.papers).getSingle();
      expect(bp.lastPage, 4);
      expect(bp.readingStatus, ReadingStatus.reading);
      expect(bp.title, 'Attention Is All You Need');
      expect(bp.year, 2017);
      expect(bp.doi, '10.5555/3295222.3295349');
      expect(File(bp.pdfPath!).readAsBytesSync(), pdf.readAsBytesSync());
      final bn = await b.db.select(b.db.notes).getSingle();
      expect(bn.content, '[{"insert":"héllo ✓\\n"}]');
      expect(bn.folderId, folder);
      expect(await b.db.select(b.db.noteTags).get(), hasLength(1));
      expect(await b.db.select(b.db.notePaperRefs).get(), hasLength(1));
      expect(await b.db.select(b.db.attachments).get(), hasLength(2));
      final bi = await (b.db.select(
        b.db.attachments,
      )..where((t) => t.id.equals(attach))).getSingle();
      expect(File(bi.path!).readAsBytesSync(), [1, 2, 3]);
      expect(
        (await b.db.select(b.db.annotations).getSingle()).pointsJson,
        '[[0.1,0.2],[0.3,0.4]]',
      );
      expect(await b.engine.pendingChanges(), 0);
      expect(await a.engine.pendingChanges(), 0);

      // Edit on B, delete on A, both propagate.
      await (b.db.update(b.db.notes)..where((n) => n.id.equals(note))).write(
        const NotesCompanion(title: Value('Renamed')),
      );
      // updated_at has one-second resolution; make the delete unambiguously
      // later than the edit.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await b.engine.sync(userId: userId);
      await a.engine.sync(userId: userId);
      expect((await a.db.select(a.db.notes).getSingle()).title, 'Renamed');

      await (a.db.delete(a.db.notes)..where((n) => n.id.equals(note))).go();
      await a.engine.sync(userId: userId);
      await b.engine.sync(userId: userId);
      expect(await b.db.select(b.db.notes).get(), isEmpty);
      expect(await b.db.select(b.db.noteTags).get(), isEmpty);
      expect(
        await b.db.select(b.db.attachments).get(),
        hasLength(1),
        reason: 'only the podcast (paper-owned) remains',
      );
      expect(await b.db.select(b.db.papers).get(), hasLength(1));

      // Nothing left to do, and a further sync is quiet.
      await b.engine.sync(userId: userId);
      expect(await b.engine.pendingChanges(), 0);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a stale write is rejected by the server (last write wins)', () async {
    final id = _id();
    final remote = SupabaseSyncRemote(client);
    Map<String, Object?> row(String name, String at) => {
      'id': id,
      'name': name,
      'created_at': '2030-01-01T00:00:00Z',
      'updated_at': at,
      'deleted_at': null,
    };

    await remote.upsertRows('folders', [row('newer', '2030-01-02T00:00:00Z')]);
    await remote.upsertRows('folders', [row('older', '2030-01-01T12:00:00Z')]);

    final rows = await remote.fetchChanges('folders');
    expect(rows.single['name'], 'newer');
  }, skip: skip);

  test('a delete is soft and reaches pullers', () async {
    final id = _id();
    final remote = SupabaseSyncRemote(client);
    await remote.upsertRows('folders', [
      {
        'id': id,
        'name': 'x',
        'created_at': '2030-01-01T00:00:00Z',
        'updated_at': '2030-01-01T00:00:00Z',
        'deleted_at': null,
      },
    ]);
    await remote.markDeleted('folders', {'id': id}, '2030-01-02T00:00:00Z');

    final rows = await remote.fetchChanges('folders');
    expect(rows.single['deleted_at'], isNotNull);
  }, skip: skip);

  test('changes come back oldest-first and the pull cursor advances', () async {
    final remote = SupabaseSyncRemote(client);
    for (final name in ['first', 'second', 'third']) {
      await remote.upsertRows('folders', [
        {
          'id': _id(),
          'name': name,
          'created_at': '2030-01-01T00:00:00Z',
          'updated_at': '2030-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ]);
    }
    final rows = await remote.fetchChanges('folders');
    expect(rows.map((r) => r['name']), ['first', 'second', 'third']);

    await a.engine.sync(userId: userId);
    final cursor =
        (await a.db.customSelect('SELECT last_pull FROM sync_meta').getSingle())
            .read<String>('last_pull');
    expect(cursor, contains(rows.last['synced_at']! as String));
  }, skip: skip);

  test('users cannot see or modify each other\'s data', () async {
    final id = _id();
    await SupabaseSyncRemote(client).upsertRows('folders', [
      {
        'id': id,
        'name': 'private',
        'created_at': '2030-01-01T00:00:00Z',
        'updated_at': '2030-01-01T00:00:00Z',
        'deleted_at': null,
      },
    ]);
    final path = '$userId/papers/secret.pdf';
    final f = File(p.join(a.dir.path, 's.pdf'))..writeAsBytesSync([1]);
    await SupabaseFileRemote(client).upload(path, f);

    final (other, otherId) = await newUser();
    final otherRemote = SupabaseSyncRemote(other);

    expect(await otherRemote.fetchChanges('folders'), isEmpty);
    await otherRemote.markDeleted('folders', {
      'id': id,
    }, '2031-01-01T00:00:00Z');
    expect(
      (await SupabaseSyncRemote(client).fetchChanges('folders'))
          .single['deleted_at'],
      isNull,
    );
    await expectLater(
      otherRemote.upsertRows('folders', [
        {
          'id': id,
          'name': 'hijack',
          'created_at': '2030-01-01T00:00:00Z',
          'updated_at': '2032-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ]),
      throwsA(anything),
    );
    await expectLater(
      SupabaseFileRemote(other).download(path),
      throwsA(anything),
    );
    await expectLater(
      SupabaseFileRemote(other).upload('$userId/papers/x.pdf', f),
      throwsA(anything),
    );
    await SupabaseFileRemote(other).upload('$otherId/papers/mine.pdf', f);
  }, skip: skip);
}
