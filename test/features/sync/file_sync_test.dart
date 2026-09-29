import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/sync/file_sync.dart';
import 'package:corplex/features/sync/sync_engine.dart';

import '../../support/fake_sync_remote.dart';

class _Device {
  _Device(this.name, FakeSyncRemote server, FakeFileRemote files) {
    dir = Directory.systemTemp.createTempSync('corplex_$name');
    db = AppDatabase.inMemoryForTesting();
    engine = SyncEngine(
      db,
      server,
      files: FileSync(db, files, (subfolder, fileName) async {
        final d = Directory(p.join(dir.path, subfolder))
          ..createSync(recursive: true);
        return p.join(d.path, fileName);
      }),
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
}
