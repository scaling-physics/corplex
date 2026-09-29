import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/database.dart';

/// Where file bytes go in the cloud. Narrow so tests can fake it.
abstract class FileRemote {
  Future<void> upload(String key, File file);

  Future<Uint8List> download(String key);

  /// Objects directly under [prefix] (e.g. `<user>/papers`).
  Future<List<RemoteObject>> list(String prefix);

  Future<void> remove(List<String> keys);
}

class RemoteObject {
  const RemoteObject(this.key, this.createdAt);

  final String key;
  final DateTime createdAt;
}

class SupabaseFileRemote implements FileRemote {
  SupabaseFileRemote(this._client);

  final SupabaseClient _client;

  static const bucket = 'files';

  @override
  Future<void> upload(String key, File file) async {
    await _client.storage
        .from(bucket)
        .upload(key, file, fileOptions: const FileOptions(upsert: true));
  }

  @override
  Future<Uint8List> download(String key) =>
      _client.storage.from(bucket).download(key);

  @override
  Future<List<RemoteObject>> list(String prefix) async {
    const page = 100;
    final found = <RemoteObject>[];
    for (var offset = 0; ; offset += page) {
      final items = await _client.storage
          .from(bucket)
          .list(
            path: prefix,
            searchOptions: SearchOptions(limit: page, offset: offset),
          );
      for (final item in items) {
        final created = DateTime.tryParse(item.createdAt ?? '');
        // Folders have no timestamps; only real objects are of interest.
        if (created != null) {
          found.add(RemoteObject('$prefix/${item.name}', created));
        }
      }
      if (items.length < page) return found;
    }
  }

  @override
  Future<void> remove(List<String> keys) async {
    if (keys.isEmpty) return;
    await _client.storage.from(bucket).remove(keys);
  }
}

/// Files larger than this aren't uploaded (see [FileSync.maxUploadBytes]).
const defaultMaxUploadBytes = 50 * 1024 * 1024;

/// Cloud objects newer than this are never treated as orphans: another
/// device may have uploaded one and not pushed the row that names it yet.
const orphanGrace = Duration(days: 1);

/// Picks a fresh local path for a downloaded file, e.g. inside the app's
/// documents folder. Injected so tests can use a temp directory.
typedef LocalPathAllocator = Future<String> Function(
  String subfolder,
  String fileName,
);

/// Moves the actual PDFs/images/audio between this device and cloud
/// storage. Metadata sync (SyncEngine) carries only `storage_key`; the file
/// paths themselves are per-device and never leave it.
///
/// Objects are keyed by row id — `<user>/papers/<id>.pdf`,
/// `<user>/attachments/<id><ext>` — so a retried upload is idempotent and
/// two devices can never disagree about where a file lives. Files are
/// immutable once attached, so there's no re-upload/versioning.
///
/// A file that fails to transfer is left for the next sync; it never blocks
/// metadata. [failures] counts what was skipped in the last pass.
class FileSync {
  FileSync(
    this._db,
    this._remote,
    this._allocate, {
    this.maxUploadBytes = defaultMaxUploadBytes,
  });

  /// Bigger files stay on this device only: they are skipped, not retried
  /// as failures, and don't count as pending changes.
  final int maxUploadBytes;

  final AppDatabase _db;
  final FileRemote _remote;
  final LocalPathAllocator _allocate;

  int failures = 0;

  /// Files over [maxUploadBytes] seen in the last upload pass.
  int tooLarge = 0;

  bool _uploadable(String path) {
    final file = File(path);
    return file.existsSync() && file.lengthSync() <= maxUploadBytes;
  }

  /// Uploads local files that have no `storage_key` yet and records the key
  /// (an ordinary write, so it is pushed with the rest of the metadata).
  Future<void> upload(String userId) async {
    tooLarge = 0;
    final papers = await (_db.select(
      _db.papers,
    )..where((t) => t.pdfPath.isNotNull() & t.storageKey.isNull())).get();
    for (final paper in papers) {
      await _guard(() async {
        final file = File(paper.pdfPath!);
        if (!file.existsSync()) return;
        if (!_uploadable(file.path)) {
          tooLarge++;
          return;
        }
        final key = '$userId/papers/${paper.id}.pdf';
        await _remote.upload(key, file);
        await (_db.update(_db.papers)..where((t) => t.id.equals(paper.id)))
            .write(PapersCompanion(storageKey: Value(key)));
      });
    }

    final attachments = await (_db.select(
      _db.attachments,
    )..where((t) => t.path.isNotNull() & t.storageKey.isNull())).get();
    for (final attachment in attachments) {
      await _guard(() async {
        final file = File(attachment.path!);
        if (!file.existsSync()) return;
        if (!_uploadable(file.path)) {
          tooLarge++;
          return;
        }
        final key =
            '$userId/attachments/${attachment.id}${p.extension(file.path)}';
        await _remote.upload(key, file);
        await (_db.update(_db.attachments)
              ..where((t) => t.id.equals(attachment.id)))
            .write(AttachmentsCompanion(storageKey: Value(key)));
      });
    }
  }

  /// Fetches files that exist in the cloud but not on this device —
  /// including ones whose local copy has gone missing (e.g. after a
  /// reinstall moved the app's storage folder).
  Future<void> download() async {
    final papers = await (_db.select(
      _db.papers,
    )..where((t) => t.storageKey.isNotNull())).get();
    for (final paper in papers) {
      if (_present(paper.pdfPath)) continue;
      await _guard(() async {
        final path = await _fetch(
          paper.storageKey!,
          'papers',
          '${paper.id}.pdf',
        );
        await _setLocalPath('papers', 'pdf_path', paper.id, path);
      });
    }

    final attachments = await (_db.select(
      _db.attachments,
    )..where((t) => t.storageKey.isNotNull())).get();
    for (final attachment in attachments) {
      if (_present(attachment.path)) continue;
      await _guard(() async {
        final path = await _fetch(
          attachment.storageKey!,
          'attachments',
          '${attachment.id}${p.extension(attachment.storageKey!)}',
        );
        await _setLocalPath('attachments', 'path', attachment.id, path);
      });
    }
  }

  /// Rows that still have a local file waiting to be uploaded.
  Future<int> pendingUploads() async {
    var count = 0;
    final papers = await (_db.select(
      _db.papers,
    )..where((t) => t.pdfPath.isNotNull() & t.storageKey.isNull())).get();
    count += papers.where((t) => _uploadable(t.pdfPath!)).length;
    final attachments = await (_db.select(
      _db.attachments,
    )..where((t) => t.path.isNotNull() & t.storageKey.isNull())).get();
    count += attachments.where((t) => _uploadable(t.path!)).length;
    return count;
  }

  /// Deletes cloud objects that no row refers to any more (a paper or
  /// attachment was deleted; nothing else removes its file). [liveKeys] must
  /// come from the *server's* rows, not just this device's, so a row this
  /// device hasn't applied can't make its file look orphaned. Local keys are
  /// kept too (unpushed rows), and anything younger than [orphanGrace].
  /// Returns how many objects were removed. Best effort: failures are
  /// ignored and retried on a later sync.
  Future<int> removeOrphans(
    String userId,
    Set<String> liveKeys, {
    DateTime? now,
  }) async {
    try {
      final local = {
        for (final r
            in await _db
                .customSelect(
                  'SELECT storage_key AS k FROM papers WHERE storage_key IS NOT NULL '
                  'UNION SELECT storage_key FROM attachments '
                  'WHERE storage_key IS NOT NULL',
                )
                .get())
          r.read<String>('k'),
      };
      final cutoff = (now ?? DateTime.now()).subtract(orphanGrace);
      final orphans = <String>[
        for (final folder in const ['papers', 'attachments'])
          for (final o in await _remote.list('$userId/$folder'))
            if (o.createdAt.isBefore(cutoff) &&
                !liveKeys.contains(o.key) &&
                !local.contains(o.key))
              o.key,
      ];
      await _remote.remove(orphans);
      return orphans.length;
    } catch (_) {
      return 0;
    }
  }

  bool _present(String? path) => path != null && File(path).existsSync();

  Future<String> _fetch(String key, String subfolder, String name) async {
    final bytes = await _remote.download(key);
    final path = await _allocate(subfolder, name);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Records where the downloaded file landed. The path is device-local, so
  /// this must not look like an edit: sync tracking is suppressed and the
  /// row's `updated_at` stays put.
  Future<void> _setLocalPath(
    String table,
    String column,
    String id,
    String path,
  ) async {
    await _db.transaction(() async {
      await _db.customStatement('UPDATE sync_meta SET applying = 1');
      try {
        await _db.customUpdate(
          'UPDATE $table SET $column = ? WHERE id = ?',
          variables: [Variable.withString(path), Variable.withString(id)],
          updates: {if (table == 'papers') _db.papers else _db.attachments},
          updateKind: UpdateKind.update,
        );
      } finally {
        await _db.customStatement('UPDATE sync_meta SET applying = 0');
      }
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      failures++;
    }
  }
}
