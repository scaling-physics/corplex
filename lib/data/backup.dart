import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Backups are a single zip:
///
///     manifest.json            format, app schema version, when, counts
///     corplex.sqlite           a consistent snapshot of the database
///     files/<path under docs>  every PDF / image / audio the data points at
///
/// File paths inside the database are device-specific (an iOS app's
/// container path even changes between installs), so the snapshot stores
/// them relative to the app's documents folder, as `@docs/…`, and restore
/// rewrites them for wherever it lands.
const backupFormat = 1;
const _dbName = 'corplex.sqlite';
const _docsMarker = '@docs/';
const _stagingDir = 'restore_staging';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes a backup of [db] (whose files live under [docsDir]) into
/// [outDir] and returns it. Safe while the app is running: the database
/// snapshot is taken with SQLite's own `VACUUM INTO`.
Future<File> createBackup(
  AppDatabase db, {
  required Directory docsDir,
  required Directory outDir,
  DateTime? now,
}) async {
  final stamp = now ?? DateTime.now();
  final work = Directory.systemTemp.createTempSync('corplex_backup');
  try {
    final snapshot = File(p.join(work.path, _dbName));
    await db.customStatement('VACUUM INTO ?', [snapshot.path]);

    // Portable paths, and the list of files worth including.
    final files = <String>{};
    final copy = sqlite3.open(snapshot.path);
    try {
      for (final table in const [
        ('papers', 'pdf_path'),
        ('attachments', 'path'),
      ]) {
        final rows = copy.select(
          'SELECT DISTINCT ${table.$2} AS path FROM ${table.$1} '
          'WHERE ${table.$2} IS NOT NULL',
        );
        for (final row in rows) {
          final path = row['path'] as String;
          if (p.isWithin(docsDir.path, path) && File(path).existsSync()) {
            files.add(path);
          }
        }
        copy.execute(
          "UPDATE ${table.$1} SET ${table.$2} = ? || substr(${table.$2}, ?) "
          'WHERE ${table.$2} LIKE ?',
          [_docsMarker, docsDir.path.length + 2, '${docsDir.path}/%'],
        );
      }
      // Trash items snapshot paths too; they're local-only and the trash
      // itself isn't worth carrying between devices.
      copy.execute('DELETE FROM trash_items');
      // A fresh device must not believe it already belongs to an account
      // or has synced.
      copy.execute('UPDATE sync_meta SET user_id = NULL, last_pull = NULL');
      copy.execute('DELETE FROM sync_tombstones');
      // Derived; each device rebuilds its own (see SearchIndex).
      copy.execute('DROP TABLE IF EXISTS search_index');
    } finally {
      copy.close();
    }

    final counts = {
      for (final t in const ['notes', 'papers', 'highlights', 'projects'])
        t: (await db.customSelect('SELECT COUNT(*) c FROM $t').getSingle())
            .read<int>('c'),
    };

    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': backupFormat,
            'schemaVersion': db.schemaVersion,
            'createdAt': stamp.toUtc().toIso8601String(),
            'counts': counts,
            'files': files.length,
          }),
        ),
      )
      ..addFile(ArchiveFile.bytes(_dbName, snapshot.readAsBytesSync()));
    for (final path in files) {
      archive.addFile(
        ArchiveFile.bytes(
          'files/${p.relative(path, from: docsDir.path).replaceAll(r'\', '/')}',
          File(path).readAsBytesSync(),
        ),
      );
    }

    outDir.createSync(recursive: true);
    final name =
        'corplex-backup-${stamp.year}-${_two(stamp.month)}-${_two(stamp.day)}'
        '-${_two(stamp.hour)}${_two(stamp.minute)}.zip';
    final out = File(p.join(outDir.path, name));
    out.writeAsBytesSync(ZipEncoder().encode(archive));
    return out;
  } finally {
    work.deleteSync(recursive: true);
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// What a backup file contains, for confirming before restoring.
class BackupInfo {
  const BackupInfo({
    required this.createdAt,
    required this.notes,
    required this.papers,
  });

  final DateTime createdAt;
  final int notes;
  final int papers;
}

/// Reads and validates a backup's manifest. Throws [BackupException] for
/// anything that isn't a Corplex backup this version can restore.
BackupInfo inspectBackup(File zip, {required int currentSchemaVersion}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  } catch (_) {
    throw const BackupException('That file isn\'t a Corplex backup.');
  }
  final manifestFile = archive.findFile('manifest.json');
  if (manifestFile == null || archive.findFile(_dbName) == null) {
    throw const BackupException('That file isn\'t a Corplex backup.');
  }
  final manifest =
      jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
  if (manifest['format'] != backupFormat) {
    throw const BackupException('This backup is from an unsupported version.');
  }
  if ((manifest['schemaVersion'] as int) > currentSchemaVersion) {
    throw const BackupException(
      'This backup was made by a newer version of Corplex. Update the app '
      'first.',
    );
  }
  final counts = (manifest['counts'] as Map).cast<String, int>();
  return BackupInfo(
    createdAt: DateTime.parse(manifest['createdAt'] as String).toLocal(),
    notes: counts['notes'] ?? 0,
    papers: counts['papers'] ?? 0,
  );
}

/// Stages [zip] to replace the library the next time the app starts. It
/// can't be swapped in while the database is open, so [applyPendingRestore]
/// does the swap at launch, before anything opens the database.
Future<void> stageRestore(
  File zip, {
  required Directory docsDir,
  required int currentSchemaVersion,
}) async {
  inspectBackup(zip, currentSchemaVersion: currentSchemaVersion);
  final staging = Directory(p.join(docsDir.path, _stagingDir));
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  for (final entry in archive) {
    if (!entry.isFile) continue;
    // Refuse anything that would escape the staging folder.
    final target = p.normalize(p.join(staging.path, entry.name));
    if (!p.isWithin(staging.path, target)) continue;
    File(target)
      ..createSync(recursive: true)
      ..writeAsBytesSync(entry.content);
  }
  File(p.join(staging.path, 'READY')).writeAsStringSync('1');
}

/// Whether a restore is waiting for the next launch.
bool hasPendingRestore(Directory docsDir) =>
    File(p.join(docsDir.path, _stagingDir, 'READY')).existsSync();

/// If a restore was staged, swaps it in: the current database is kept as
/// `corplex.sqlite.before-restore` (one level of undo), the backup's
/// database and files replace it, and paths are rewritten for this device.
/// Must run before the database is opened. Returns whether it restored.
Future<bool> applyPendingRestore(Directory docsDir) async {
  if (!hasPendingRestore(docsDir)) return false;
  final staging = Directory(p.join(docsDir.path, _stagingDir));
  final staged = File(p.join(staging.path, _dbName));
  if (!staged.existsSync()) {
    staging.deleteSync(recursive: true);
    return false;
  }

  final dbFile = File(p.join(docsDir.path, _dbName));
  final keep = File('${dbFile.path}.before-restore');
  if (dbFile.existsSync()) {
    if (keep.existsSync()) keep.deleteSync();
    dbFile.renameSync(keep.path);
  }
  for (final suffix in const ['-wal', '-shm']) {
    final sidecar = File('${dbFile.path}$suffix');
    if (sidecar.existsSync()) sidecar.deleteSync();
  }
  staged.renameSync(dbFile.path);

  final filesDir = Directory(p.join(staging.path, 'files'));
  if (filesDir.existsSync()) {
    for (final entity in filesDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final target = File(
        p.join(docsDir.path, p.relative(entity.path, from: filesDir.path)),
      );
      target.parent.createSync(recursive: true);
      entity.renameSync(target.path);
    }
  }

  final restored = sqlite3.open(dbFile.path);
  try {
    for (final table in const [
      ('papers', 'pdf_path'),
      ('attachments', 'path'),
    ]) {
      restored.execute(
        "UPDATE ${table.$1} SET ${table.$2} = ? || substr(${table.$2}, ?) "
        'WHERE ${table.$2} LIKE ?',
        ['${docsDir.path}/', _docsMarker.length + 1, '$_docsMarker%'],
      );
    }
  } finally {
    restored.close();
  }
  staging.deleteSync(recursive: true);
  return true;
}
