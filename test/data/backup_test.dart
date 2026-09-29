import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:corplex/data/backup.dart';
import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';

/// A database in a real file, like the app's, inside [docs].
AppDatabase _openIn(Directory docs) => AppDatabase.forTesting(
  NativeDatabase(
    File(p.join(docs.path, 'corplex.sqlite')),
    setup: (d) => d.execute('PRAGMA foreign_keys = ON;'),
  ),
);

void main() {
  late Directory root;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = Directory.systemTemp.createTempSync('corplex_backup_test');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Directory dir(String name) =>
      Directory(p.join(root.path, name))..createSync(recursive: true);

  Future<File> makeBackup(Directory docs) async {
    final db = _openIn(docs);
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Lecture'),
          ),
        );
    final pdf = File(p.join(docs.path, 'papers', 'attention.pdf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([37, 80, 68, 70, 1, 2, 3]);
    final audio = File(p.join(docs.path, 'attachments', 'overview.m4a'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);
    await db
        .into(db.papers)
        .insert(
          PapersCompanion.insert(
            id: const Value('p1'),
            title: 'Attention',
            pdfPath: Value(pdf.path),
          ),
        );
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: const Value('a1'),
            noteId: const Value('n1'),
            type: AttachmentType.podcast,
            path: Value(audio.path),
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            paperId: 'p1',
            pageNumber: 2,
            quote: 'q',
            rectsJson: '[]',
          ),
        );
    await db.customStatement(
      "UPDATE sync_meta SET user_id = 'someone', last_pull = '{}'",
    );
    final zip = await createBackup(
      db,
      docsDir: docs,
      outDir: dir('out'),
      now: DateTime(2026, 9, 30, 14, 5),
    );
    await db.close();
    return zip;
  }

  test('a backup is named by date and describes its contents', () async {
    final docs = dir('old-phone');
    final zip = await makeBackup(docs);

    expect(p.basename(zip.path), 'corplex-backup-2026-09-30-1405.zip');
    final info = inspectBackup(zip, currentSchemaVersion: 99);
    expect(info.notes, 1);
    expect(info.papers, 1);
    expect(info.createdAt.year, 2026);

    final names = ZipDecoder()
        .decodeBytes(zip.readAsBytesSync())
        .map((f) => f.name)
        .toSet();
    expect(
      names,
      containsAll([
        'manifest.json',
        'corplex.sqlite',
        'files/papers/attention.pdf',
        'files/attachments/overview.m4a',
      ]),
    );
  });

  test('restoring on a different device brings back data and files, with paths fixed', () async {
    final zip = await makeBackup(dir('old-phone'));
    final newDocs = dir('new-phone');

    await stageRestore(
      zip,
      docsDir: newDocs,
      currentSchemaVersion: AppDatabase.forTesting(NativeDatabase.memory())
          .schemaVersion,
    );
    expect(hasPendingRestore(newDocs), isTrue);
    expect(await applyPendingRestore(newDocs), isTrue);
    expect(hasPendingRestore(newDocs), isFalse);
    expect(
      Directory(p.join(newDocs.path, 'restore_staging')).existsSync(),
      isFalse,
    );

    final db = _openIn(newDocs);
    addTearDown(db.close);
    expect((await db.select(db.notes).getSingle()).title, 'Lecture');
    expect(await db.select(db.highlights).get(), hasLength(1));

    final paper = await db.select(db.papers).getSingle();
    expect(paper.pdfPath, p.join(newDocs.path, 'papers', 'attention.pdf'));
    expect(File(paper.pdfPath!).readAsBytesSync(), [37, 80, 68, 70, 1, 2, 3]);
    final attachment = await db.select(db.attachments).getSingle();
    expect(File(attachment.path!).readAsBytesSync(), [9, 9]);

    // The new device doesn't inherit the old device's sync identity.
    final meta = await db
        .customSelect('SELECT user_id, last_pull FROM sync_meta')
        .getSingle();
    expect(meta.read<String?>('user_id'), isNull);
    expect(meta.read<String?>('last_pull'), isNull);
  });

  test(
    'restoring over an existing library keeps the old database as an undo',
    () async {
      final zip = await makeBackup(dir('old-phone'));
      final docs = dir('this-phone');
      final current = _openIn(docs);
      await current
          .into(current.notes)
          .insert(NotesCompanion.insert(title: const Value('Newer work')));
      await current.close();

      await stageRestore(zip, docsDir: docs, currentSchemaVersion: 99);
      await applyPendingRestore(docs);

      final restored = _openIn(docs);
      addTearDown(restored.close);
      expect(
        (await restored.select(restored.notes).getSingle()).title,
        'Lecture',
      );
      final before = File(p.join(docs.path, 'corplex.sqlite.before-restore'));
      expect(before.existsSync(), isTrue);
    },
  );

  test(
    'files that are not backups are rejected with a clear message',
    () async {
      final junk = File(p.join(root.path, 'junk.zip'))
        ..writeAsStringSync('not a zip');
      expect(
        () => inspectBackup(junk, currentSchemaVersion: 99),
        throwsA(isA<BackupException>()),
      );

      final wrong = File(p.join(root.path, 'wrong.zip'))
        ..writeAsBytesSync(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile.string('hello.txt', 'hi')),
          ),
        );
      expect(
        () => inspectBackup(wrong, currentSchemaVersion: 99),
        throwsA(isA<BackupException>()),
      );
    },
  );

  test('a backup from a newer app version is refused', () async {
    final zip = await makeBackup(dir('old-phone'));
    expect(
      () => inspectBackup(zip, currentSchemaVersion: 1),
      throwsA(
        isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('newer version'),
        ),
      ),
    );
  });

  test('archive entries cannot escape the staging folder', () async {
    final good = await makeBackup(dir('old-phone'));
    final archive = ZipDecoder().decodeBytes(good.readAsBytesSync())
      ..addFile(ArchiveFile.string('../../evil.txt', 'owned'));
    final evil = File(p.join(root.path, 'evil.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final docs = dir('victim');

    await stageRestore(evil, docsDir: docs, currentSchemaVersion: 99);

    expect(File(p.join(root.path, 'evil.txt')).existsSync(), isFalse);
    expect(File(p.join(docs.path, '..', 'evil.txt')).existsSync(), isFalse);
  });

  test('nothing staged means nothing happens', () async {
    expect(await applyPendingRestore(dir('empty')), isFalse);
  });
}
