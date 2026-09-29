import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/sync/sync_remote.dart';
import 'package:corplex/features/sync/transfer_settings.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:corplex/features/sync/file_sync.dart';
import 'package:corplex/features/sync/sync_engine.dart';

import '../../support/fake_sync_remote.dart';

class _Device {
  _Device(
    this.name,
    FakeSyncRemote server,
    FakeFileRemote files, {
    int? maxUploadBytes,
    PolicyResolver? policy,
  }) {
    dir = Directory.systemTemp.createTempSync('corplex_$name');
    db = AppDatabase.inMemoryForTesting();
    engine = SyncEngine(
      db,
      server,
      files: FileSync(
        db,
        files,
        (subfolder, fileName) async {
          final d = Directory(p.join(dir.path, subfolder))
            ..createSync(recursive: true);
          return p.join(d.path, fileName);
        },
        maxUploadBytes: maxUploadBytes ?? defaultMaxUploadBytes,
        policy: policy,
      ),
    );
  }

  final String name;
  late final Directory dir;
  late final AppDatabase db;
  late final SyncEngine engine;

  File writeFile(String fileName, List<int> bytes) =>
      File(p.join(dir.path, fileName))..writeAsBytesSync(bytes);

  Future<void> sync([String user = 'u1']) => engine.sync(userId: user);

  Future<void> dispose() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late FakeSyncRemote server;
  late FakeFileRemote files;
  late _Device a;
  late _Device b;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    server = FakeSyncRemote();
    files = FakeFileRemote();
    a = _Device('a', server, files);
    b = _Device('b', server, files);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('a PDF added on one device is downloaded on the other', () async {
    final pdf = a.writeFile('paper.pdf', [1, 2, 3, 4]);
    await a.db
        .into(a.db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'T',
            pdfPath: Value(pdf.path),
          ),
        );

    await a.sync();
    await b.sync();

    final paper = await b.db.select(b.db.papers).getSingle();
    expect(paper.storageKey, 'u1/papers/p1.pdf');
    expect(File(paper.pdfPath!).readAsBytesSync(), [1, 2, 3, 4]);
    expect(paper.pdfPath, startsWith(b.dir.path));
    expect(
      (await a.db.select(a.db.papers).getSingle()).pdfPath,
      pdf.path,
      reason: 'the uploader keeps its own file',
    );
    // Storing the download path is not an edit and must not sync back.
    expect(await b.engine.pendingChanges(), 0);
  });

  test('attachment files keep their extension', () async {
    final img = a.writeFile('shot.png', [9, 9]);
    await a.db
        .into(a.db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await a.db
        .into(a.db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: const Value('at1'),
            noteId: const Value('n1'),
            type: AttachmentType.image,
            path: Value(img.path),
          ),
        );

    await a.sync();
    await b.sync();

    final attachment = await b.db.select(b.db.attachments).getSingle();
    expect(p.extension(attachment.path!), '.png');
    expect(File(attachment.path!).readAsBytesSync(), [9, 9]);
  });

  test('a failed upload still syncs metadata, and retries later', () async {
    final pdf = a.writeFile('paper.pdf', [7]);
    await a.db
        .into(a.db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'T',
            pdfPath: Value(pdf.path),
          ),
        );

    files.failing = true;
    await expectLater(a.sync(), throwsA(isA<SyncFilesIncomplete>()));
    await b.sync();
    expect((await b.db.select(b.db.papers).getSingle()).title, 'T');
    expect((await b.db.select(b.db.papers).getSingle()).pdfPath, isNull);

    files.failing = false;
    await a.sync();
    await b.sync();
    expect((await b.db.select(b.db.papers).getSingle()).pdfPath, isNotNull);
  });

  test('a file that vanished locally is downloaded again', () async {
    final pdf = a.writeFile('paper.pdf', [5, 5]);
    await a.db
        .into(a.db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'T',
            pdfPath: Value(pdf.path),
          ),
        );
    await a.sync();
    pdf.deleteSync();

    await a.sync();

    final path = (await a.db.select(a.db.papers).getSingle()).pdfPath!;
    expect(File(path).readAsBytesSync(), [5, 5]);
  });

  test('watchers refresh after a pull', () async {
    await a.db
        .into(a.db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('hi'),
          ),
        );
    await a.sync();

    final seen = <int>[];
    final sub = b.db
        .select(b.db.notes)
        .watch()
        .listen((rows) => seen.add(rows.length));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await b.sync();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();

    expect(seen, [0, 1]);
  });

  group('erasing local data', () {
    test('removes rows, files and pending state', () async {
      final pdf = a.writeFile('paper.pdf', [1]);
      await a.db
          .into(a.db.papers)
          .insert(
            PapersCompanion.insert(
              id: const Value('p1'),
              title: 'T',
              pdfPath: Value(pdf.path),
            ),
          );
      await a.sync();
      await b.sync();
      final downloaded = (await b.db.select(b.db.papers).getSingle()).pdfPath!;

      await b.engine.eraseLocalData();

      expect(await b.db.select(b.db.papers).get(), isEmpty);
      expect(File(downloaded).existsSync(), isFalse);
      expect(await b.engine.pendingChanges(), 0);
      expect(
        server.tables['papers']!.values.length,
        1,
        reason: 'erasing must not delete anything in the cloud',
      );
    });

    test('lets a device switch accounts', () async {
      await a.db
          .into(a.db.folders)
          .insert(FoldersCompanion.insert(name: 'mine'));
      await a.sync('u1');
      await expectLater(a.sync('u2'), throwsA(isA<SyncAccountMismatch>()));

      await a.engine.eraseLocalData();
      // The second account's (empty) cloud library; the fake server has no
      // per-user isolation, which the real one gets from row-level security.
      await SyncEngine(a.db, FakeSyncRemote()).sync(userId: 'u2');

      expect(await a.db.select(a.db.folders).get(), isEmpty);
      // ...and nothing of u1's was uploaded into u2's library.
      expect(server.tables['folders']!.values, hasLength(1));
    });

    test('erasing then syncing the same account restores everything', () async {
      await a.db
          .into(a.db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('keep'),
            ),
          );
      await a.sync();

      await a.engine.eraseLocalData();
      expect(await a.db.select(a.db.notes).get(), isEmpty);
      await a.sync();

      expect((await a.db.select(a.db.notes).getSingle()).title, 'keep');
    });
  });

  test('pendingChanges counts unsynced edits, deletes and files', () async {
    expect(await a.engine.pendingChanges(), 0);
    final pdf = a.writeFile('paper.pdf', [1]);
    await a.db
        .into(a.db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'T',
            pdfPath: Value(pdf.path),
          ),
        );
    await a.db
        .into(a.db.notes)
        .insert(NotesCompanion.insert(id: const Value('n1')));
    await a.sync();
    expect(await a.engine.pendingChanges(), 0);

    await (a.db.delete(a.db.notes)..where((n) => n.id.equals('n1'))).go();

    expect(await a.engine.pendingChanges(), 1);
  });

  group('cloud cleanup', () {
    Future<void> addPaper(String id, File pdf) => a.db
        .into(a.db.papers)
        .insert(
          PapersCompanion.insert(
            id: Value(id),
            title: id,
            pdfPath: Value(pdf.path),
          ),
        );

    // Row stamps have one-second resolution and the key write bumps
    // `updated_at` a second ahead, so a delete in the same second would
    // (correctly) lose to it. Real deletes are never that quick.
    Future<void> later() =>
        Future<void>.delayed(const Duration(milliseconds: 2100));

    void age(String key) =>
        files.created[key] = DateTime.now().subtract(const Duration(days: 3));

    test('the file of a deleted paper is removed from storage', () async {
      await addPaper('p1', a.writeFile('1.pdf', [1]));
      await addPaper('p2', a.writeFile('2.pdf', [2]));
      await a.sync();
      expect(files.objects.keys, hasLength(2));
      age('u1/papers/p1.pdf');
      age('u1/papers/p2.pdf');

      await later();
      await (a.db.delete(a.db.papers)..where((t) => t.id.equals('p1'))).go();
      await a.sync();

      expect(files.objects.keys, ['u1/papers/p2.pdf']);
    });

    test(
      'a fresh object is left alone (another device may be mid-upload)',
      () async {
        files.objects['u1/papers/other.pdf'] = Uint8List.fromList([1]);
        files.created['u1/papers/other.pdf'] = DateTime.now();
        await a.sync();
        expect(files.objects.keys, contains('u1/papers/other.pdf'));
      },
    );

    test('an object a server row still names is kept', () async {
      await addPaper('p1', a.writeFile('1.pdf', [1]));
      await a.sync();
      age('u1/papers/p1.pdf');
      // This device never applied the row (e.g. its parent is missing).
      await b.sync();
      expect(files.objects.keys, contains('u1/papers/p1.pdf'));
    });

    test('nothing is removed while the server is missing a table', () async {
      files.objects['u1/papers/x.pdf'] = Uint8List.fromList([1]);
      age('u1/papers/x.pdf');
      server.missingTables.add('projects');
      await expectLater(a.sync(), throwsA(isA<SyncServerOutdated>()));
      expect(files.objects.keys, contains('u1/papers/x.pdf'));
    });

    test('restoring a trashed paper uploads its file again', () async {
      await addPaper('p1', a.writeFile('1.pdf', [1]));
      await a.sync();
      age('u1/papers/p1.pdf');
      await later();
      final trashId = await trashPaper(a.db, 'p1');
      await a.sync(); // deletes the row, then cleanup removes the object
      expect(files.objects, isEmpty);

      await restoreFromTrash(a.db, trashId);
      await a.sync();
      await b.sync();

      expect(files.objects.keys, ['u1/papers/p1.pdf']);
      final paper = await b.db.select(b.db.papers).getSingle();
      expect(File(paper.pdfPath!).readAsBytesSync(), [1]);
    });
  });

  group('size limit', () {
    test(
      'a file over the limit stays local without failing the sync',
      () async {
        final small = _Device('small', server, files, maxUploadBytes: 3);
        addTearDown(small.dispose);
        final big = small.writeFile('big.pdf', [1, 2, 3, 4]);
        final ok = small.writeFile('ok.pdf', [1, 2]);
        for (final (id, f) in [('big', big), ('ok', ok)]) {
          await small.db
              .into(small.db.papers)
              .insert(
                PapersCompanion.insert(
                  id: Value(id),
                  title: id,
                  pdfPath: Value(f.path),
                ),
              );
        }
        // Two unpushed rows plus the one file that can go up.
        expect(await small.engine.pendingChanges(), 3);

        await small.sync(); // must not throw

        expect(files.objects.keys, ['u1/papers/ok.pdf']);
        final row = await (small.db.select(
          small.db.papers,
        )..where((t) => t.id.equals('big'))).getSingle();
        expect(row.storageKey, isNull);
        expect(await small.engine.pendingChanges(), 0);
      },
    );
  });

  group('transfer policy', () {
    Future<void> addPdf(_Device d, String id, List<int> bytes) => d.db
        .into(d.db.papers)
        .insert(
          PapersCompanion.insert(
            id: Value(id),
            title: id,
            pdfPath: Value(d.writeFile('$id.pdf', bytes).path),
          ),
        );

    test('uploads wait for an allowed network, metadata does not', () async {
      var policy = const FileTransferPolicy(upload: false);
      final phone = _Device('phone', server, files, policy: () async => policy);
      addTearDown(phone.dispose);
      await addPdf(phone, 'p1', [1]);

      await phone.sync();
      expect(files.objects, isEmpty);
      expect((await b.db.select(b.db.papers).get()), isEmpty);
      await b.sync();
      expect(await b.db.select(b.db.papers).getSingle(), isNotNull);
      expect(await phone.engine.pendingChanges(), 1, reason: 'file waits');

      policy = FileTransferPolicy.always;
      await phone.sync();
      expect(files.objects.keys, ['u1/papers/p1.pdf']);
      expect(await phone.engine.pendingChanges(), 0);
    });

    test('on-demand devices fetch a file only when asked', () async {
      final lazy = _Device(
        'lazy',
        server,
        files,
        policy: () async => const FileTransferPolicy(autoDownload: false),
      );
      addTearDown(lazy.dispose);
      await addPdf(a, 'p1', [4, 2]);
      await a.sync();

      await lazy.sync();
      var paper = await lazy.db.select(lazy.db.papers).getSingle();
      expect(paper.storageKey, isNotNull);
      expect(paper.pdfPath, isNull, reason: 'not downloaded in the background');

      expect(await lazy.engine.fetchFile(paperId: 'p1'), isTrue);
      paper = await lazy.db.select(lazy.db.papers).getSingle();
      expect(File(paper.pdfPath!).readAsBytesSync(), [4, 2]);
      expect(await lazy.engine.pendingChanges(), 0);
    });

    test(
      'an on-demand attachment fetch, and a failed one reports false',
      () async {
        final lazy = _Device(
          'lazy',
          server,
          files,
          policy: () async => const FileTransferPolicy(autoDownload: false),
        );
        addTearDown(lazy.dispose);
        await a.db
            .into(a.db.notes)
            .insert(NotesCompanion.insert(id: const Value('n1')));
        await a.db
            .into(a.db.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: const Value('at1'),
                noteId: const Value('n1'),
                type: AttachmentType.podcast,
                path: Value(a.writeFile('talk.m4a', [8]).path),
              ),
            );
        await a.sync();
        await lazy.sync();

        files.failing = true;
        expect(await lazy.engine.fetchFile(attachmentId: 'at1'), isFalse);
        files.failing = false;
        expect(await lazy.engine.fetchFile(attachmentId: 'at1'), isTrue);
        final row = await lazy.db.select(lazy.db.attachments).getSingle();
        expect(p.extension(row.path!), '.m4a');
      },
    );

    test('policyFor: Wi-Fi only, on-demand, and both', () {
      expect(policyFor(TransferSettings(), unmetered: false).upload, isFalse);
      final wifi = policyFor(TransferSettings(), unmetered: true);
      expect((wifi.upload, wifi.autoDownload), (true, true));
      final demand = policyFor(
        TransferSettings(onDemand: true),
        unmetered: true,
      );
      expect((demand.upload, demand.autoDownload), (true, false));
      final anyNetwork = policyFor(
        TransferSettings(wifiOnly: false),
        unmetered: false,
      );
      expect((anyNetwork.upload, anyNetwork.autoDownload), (true, true));
      expect(isUnmetered([ConnectivityResult.mobile]), isFalse);
      expect(
        isUnmetered([ConnectivityResult.mobile, ConnectivityResult.wifi]),
        isTrue,
      );
      expect(isUnmetered([ConnectivityResult.ethernet]), isTrue);
      expect(isUnmetered([ConnectivityResult.none]), isFalse);
    });
  });
}
