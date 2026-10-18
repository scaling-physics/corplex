import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'note_crypto.dart';

export 'note_crypto.dart'
    show isLockedContent, isRedactedBase, lockedKeyId, redactedBody;

/// Keeps notes keys in the device keychain behind Face ID / Touch ID /
/// fingerprint, so unlocking needn't type the password. A seam: the default
/// [NoBiometrics] does nothing (tests, and devices without biometrics);
/// `main()` installs the real one.
abstract class BiometricKeyStore {
  /// Whether this device can do it at all (hardware, enrolment, keychain).
  Future<bool> available();

  /// Whether keys are stored (the reader turned it on, on this device).
  Future<bool> enabled();

  /// Stores the unlocked keys (id → bytes), replacing any stored before.
  Future<void> store(Map<String, List<int>> keys);

  /// Asks for biometrics, then returns the stored keys; null if the reader
  /// cancelled, failed, or nothing is stored.
  Future<Map<String, List<int>>?> read({required String reason});

  Future<void> clear();
}

class NoBiometrics implements BiometricKeyStore {
  const NoBiometrics();

  @override
  Future<bool> available() async => false;
  @override
  Future<bool> enabled() async => false;
  @override
  Future<void> store(Map<String, List<int>> keys) async {}
  @override
  Future<Map<String, List<int>>?> read({required String reason}) async => null;
  @override
  Future<void> clear() async {}
}

final biometricKeyStoreProvider = Provider<BiometricKeyStore>(
  (ref) => const NoBiometrics(),
);

/// A note is locked but its key isn't unlocked (or it's locked under a
/// password that has since been reset and not entered).
class NoteLockedException implements Exception {
  const NoteLockedException();
}

/// The notes password and the unlocked session.
///
/// One password for every locked note (`NoteKeys` holds it as wrapped
/// keys). Unlocking puts the notes keys in memory — never on disk, except
/// in the keychain when biometrics are on — until [lockNow], the app going
/// to the background, or [autoLockAfter] without [touch].
///
/// Everything that turns a locked body into text or back goes through
/// [decryptBody] / [encryptBody]; [lockNote] / [removeLock] convert a note
/// and all its saved versions in one transaction.
class NoteLockService extends ChangeNotifier {
  NoteLockService(
    this._db, {
    NoteCrypto? crypto,
    this._biometrics = const NoBiometrics(),
    this.autoLockAfter = const Duration(minutes: 5),
    this.inlineKdf = false,
  }) : _crypto = crypto ?? NoteCrypto();

  final AppDatabase _db;
  final NoteCrypto _crypto;
  final BiometricKeyStore _biometrics;

  /// Idle time after which unlocked notes lock again.
  final Duration autoLockAfter;

  /// Run the password derivation on the calling isolate (tests).
  final bool inlineKdf;

  final _keys = <String, List<int>>{};
  Timer? _idle;

  // ---- The password (NoteKeys) ----

  /// Every notes key row, newest first. The newest is the *current* key:
  /// new locks use it.
  Future<List<NoteKeyRow>> _rows() =>
      (_db.select(_db.noteKeys)..orderBy([
            (k) => OrderingTerm.desc(k.createdAt),
            (k) => OrderingTerm.desc(k.id),
          ]))
          .get();

  Future<bool> hasPassword() async => (await _rows()).isNotEmpty;

  /// Updates when a password is set, changed or reset (here or by sync).
  Stream<bool> watchHasPassword() => _db
      .select(_db.noteKeys)
      .watch()
      .map((rows) => rows.isNotEmpty)
      .distinct();

  Future<String?> hint() async {
    final rows = await _rows();
    return rows.isEmpty ? null : rows.first.hint;
  }

  /// Sets the first notes password and unlocks. Use [changePassword] once
  /// one exists.
  Future<void> setPassword(String password, {String? hint}) async {
    if (await hasPassword()) {
      throw StateError('A notes password already exists');
    }
    await _addKey(password, hint: hint);
  }

  /// Forgotten password: a new key under a new password becomes current.
  /// Notes locked under the old one stay locked until it's entered again
  /// (nothing can recover them otherwise — that's the point).
  Future<void> resetPassword(String password, {String? hint}) =>
      _addKey(password, hint: hint);

  Future<void> _addKey(String password, {String? hint}) async {
    final key = _crypto.newNoteKey();
    final salt = _crypto.newSalt();
    final kek = await _crypto.deriveKek(
      password,
      salt,
      _crypto.iterations,
      inline: inlineKdf,
    );
    final id = const Uuid().v4();
    // The newest key is the current one, and createdAt has one-second
    // resolution: stamp a new key strictly after every existing one, so a
    // reset in the same second as the first password still wins.
    final rows = await _rows();
    var createdAt = DateTime.now();
    if (rows.isNotEmpty) {
      final next = rows.first.createdAt.add(const Duration(seconds: 1));
      if (!createdAt.isAfter(next)) createdAt = next;
    }
    await _db
        .into(_db.noteKeys)
        .insert(
          NoteKeysCompanion.insert(
            id: Value(id),
            createdAt: Value(createdAt),
            kdf: const Value(NoteCrypto.kdfName),
            iterations: _crypto.iterations,
            salt: base64.encode(salt),
            wrappedKey: await _crypto.wrap(kek, key),
            hint: Value(_blankToNull(hint)),
          ),
        );
    _keys[id] = key;
    await _refreshBiometrics();
    _armIdle();
    notifyListeners();
  }

  /// Re-wraps every key [oldPassword] opens under [newPassword]. False if
  /// [oldPassword] opens none.
  Future<bool> changePassword(
    String oldPassword,
    String newPassword, {
    String? hint,
  }) async {
    final opened = await _open(oldPassword);
    if (opened.isEmpty) return false;
    await _db.transaction(() async {
      for (final (row, key) in opened) {
        final salt = _crypto.newSalt();
        final kek = await _crypto.deriveKek(
          newPassword,
          salt,
          _crypto.iterations,
          inline: inlineKdf,
        );
        await (_db.update(
          _db.noteKeys,
        )..where((k) => k.id.equals(row.id))).write(
          NoteKeysCompanion(
            kdf: const Value(NoteCrypto.kdfName),
            iterations: Value(_crypto.iterations),
            salt: Value(base64.encode(salt)),
            wrappedKey: Value(await _crypto.wrap(kek, key)),
            hint: Value(_blankToNull(hint)),
            updatedAt: Value(DateTime.now()),
          ),
        );
        _keys[row.id] = key;
      }
    });
    _armIdle();
    notifyListeners();
    return true;
  }

  // ---- The session ----

  /// Whether the current key is unlocked, so notes can be locked and new
  /// locked content written.
  Future<bool> isUnlocked() async {
    final rows = await _rows();
    return rows.isNotEmpty && _keys.containsKey(rows.first.id);
  }

  /// Whether some key is unlocked (sync-free, for the UI's quick checks).
  bool get anyUnlocked => _keys.isNotEmpty;

  /// Whether [content] can be read right now: not locked, or locked with
  /// a key that's unlocked.
  bool canRead(String content) {
    final id = lockedKeyId(content);
    return id == null || _keys.containsKey(id);
  }

  /// Unlocks every key [password] opens. False if it opens none (wrong
  /// password).
  Future<bool> unlock(String password) async {
    final opened = await _open(password);
    if (opened.isEmpty) return false;
    for (final (row, key) in opened) {
      _keys[row.id] = key;
    }
    await _refreshBiometrics();
    _armIdle();
    notifyListeners();
    return true;
  }

  Future<List<(NoteKeyRow, List<int>)>> _open(String password) async {
    final opened = <(NoteKeyRow, List<int>)>[];
    for (final row in await _rows()) {
      final kek = await _crypto.deriveKek(
        password,
        base64.decode(row.salt),
        row.iterations,
        inline: inlineKdf,
      );
      final key = await _crypto.unwrap(kek, row.wrappedKey);
      if (key != null) opened.add((row, key));
    }
    return opened;
  }

  /// Whether biometric unlock is set up on this device.
  Future<bool> biometricsEnabled() => _biometrics.enabled();

  Future<bool> biometricsAvailable() => _biometrics.available();

  /// Turns biometric unlock on (needs the notes unlocked, to store their
  /// keys) or off.
  Future<void> setBiometrics(bool on) async {
    if (!on) {
      await _biometrics.clear();
    } else {
      if (_keys.isEmpty) throw const NoteLockedException();
      await _biometrics.store(Map.of(_keys));
    }
    notifyListeners();
  }

  /// Unlocks with Face ID / Touch ID / fingerprint. False if cancelled,
  /// failed or not set up.
  Future<bool> unlockWithBiometrics({
    String reason = 'Unlock your locked notes',
  }) async {
    if (!await _biometrics.enabled()) return false;
    final stored = await _biometrics.read(reason: reason);
    if (stored == null || stored.isEmpty) return false;
    final ids = {for (final r in await _rows()) r.id};
    stored.removeWhere((id, _) => !ids.contains(id));
    if (stored.isEmpty) return false;
    _keys.addAll(stored);
    _armIdle();
    notifyListeners();
    return true;
  }

  /// Keeps the keychain copy in step with the unlocked keys (after a
  /// change or reset adds one).
  Future<void> _refreshBiometrics() async {
    if (await _biometrics.enabled()) {
      await _biometrics.store(Map.of(_keys));
    }
  }

  /// Locks every locked note again now.
  void lockNow() {
    _idle?.cancel();
    if (_keys.isEmpty) return;
    _keys.clear();
    notifyListeners();
  }

  /// Marks activity in a locked note, postponing the auto-lock.
  void touch() {
    if (_keys.isNotEmpty) _armIdle();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(autoLockAfter, lockNow);
  }

  // ---- Bodies ----

  /// [body] (as stored: Delta JSON) locked for [noteId] with the current
  /// key. Throws [NoteLockedException] if the notes aren't unlocked.
  Future<String> encryptBody(String noteId, String body) async {
    final rows = await _rows();
    if (rows.isEmpty) throw StateError('No notes password set');
    final key = _keys[rows.first.id];
    if (key == null) throw const NoteLockedException();
    touch();
    return _crypto.encrypt(NoteKey(rows.first.id, key), noteId, body);
  }

  /// [content] made readable: returned as is if it isn't locked. Throws
  /// [NoteLockedException] if its key isn't unlocked, or
  /// [NoteDecryptException] if it's damaged.
  Future<String> decryptBody(String noteId, String content) async {
    final id = lockedKeyId(content);
    if (id == null) return content;
    final key = _keys[id];
    if (key == null) throw const NoteLockedException();
    touch();
    return _crypto.decrypt(NoteKey(id, key), noteId, content);
  }

  /// Locks note [noteId]: its body and every saved version are encrypted
  /// with the current key, in one transaction. The sync engine's merge
  /// base for them (a plain copy of the previous version, kept until the
  /// next push) is redacted to a fingerprint, so no plain text is left
  /// behind in the database (`secure_delete` zeroes the freed pages).
  /// Already-locked bodies are left as they are.
  Future<void> lockNote(String noteId) async {
    if (!await isUnlocked()) throw const NoteLockedException();
    await _db.transaction(() async {
      final note = await (_db.select(
        _db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      if (!isLockedContent(note.content)) {
        await (_db.update(_db.notes)..where((n) => n.id.equals(noteId))).write(
          NotesCompanion(
            content: Value(await encryptBody(noteId, note.content)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      final versions = await (_db.select(
        _db.noteVersions,
      )..where((v) => v.noteId.equals(noteId))).get();
      for (final v in versions) {
        if (isLockedContent(v.content)) continue;
        await (_db.update(
          _db.noteVersions,
        )..where((r) => r.id.equals(v.id))).write(
          NoteVersionsCompanion(
            content: Value(await encryptBody(noteId, v.content)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      // Comments quote the text: encrypt their quote and body too.
      final comments = await (_db.select(
        _db.noteComments,
      )..where((c) => c.noteId.equals(noteId))).get();
      for (final c in comments) {
        await (_db.update(
          _db.noteComments,
        )..where((r) => r.id.equals(c.id))).write(
          NoteCommentsCompanion(
            quote: Value(
              isLockedContent(c.quote)
                  ? c.quote
                  : await encryptBody(noteId, c.quote),
            ),
            body: Value(
              isLockedContent(c.body)
                  ? c.body
                  : await encryptBody(noteId, c.body),
            ),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      await _redactCommentBase([for (final c in comments) c.id]);
      await _redactMergeBase('notes', [noteId]);
      await _redactMergeBase('note_versions', [for (final v in versions) v.id]);
    });
  }

  /// Takes the lock off note [noteId] (and its versions). Needs its key
  /// unlocked.
  Future<void> removeLock(String noteId) async {
    await _db.transaction(() async {
      final note = await (_db.select(
        _db.notes,
      )..where((n) => n.id.equals(noteId))).getSingle();
      if (isLockedContent(note.content)) {
        await (_db.update(_db.notes)..where((n) => n.id.equals(noteId))).write(
          NotesCompanion(
            content: Value(await decryptBody(noteId, note.content)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      final versions = await (_db.select(
        _db.noteVersions,
      )..where((v) => v.noteId.equals(noteId))).get();
      for (final v in versions) {
        if (!isLockedContent(v.content)) continue;
        await (_db.update(
          _db.noteVersions,
        )..where((r) => r.id.equals(v.id))).write(
          NoteVersionsCompanion(
            content: Value(await decryptBody(noteId, v.content)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      final comments = await (_db.select(
        _db.noteComments,
      )..where((c) => c.noteId.equals(noteId))).get();
      for (final c in comments) {
        await (_db.update(
          _db.noteComments,
        )..where((r) => r.id.equals(c.id))).write(
          NoteCommentsCompanion(
            quote: Value(await decryptBody(noteId, c.quote)),
            body: Value(await decryptBody(noteId, c.body)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Like [_redactMergeBase] for comments, whose text is in `quote` and
  /// `body` rather than `content`.
  Future<void> _redactCommentBase(List<String> ids) async {
    for (final id in ids) {
      final rows = await _db
          .customSelect(
            'SELECT data FROM sync_base WHERE table_name = ? '
            "AND row_key = json_object('id', ?)",
            variables: [
              Variable.withString('note_comments'),
              Variable.withString(id),
            ],
          )
          .get();
      if (rows.isEmpty) continue;
      final data = jsonDecode(rows.single.read<String>('data'));
      if (data is! Map<String, dynamic>) continue;
      var changed = false;
      for (final k in const ['quote', 'body']) {
        final v = data[k];
        if (v is String &&
            v.isNotEmpty &&
            !isLockedContent(v) &&
            !isRedactedBase(v)) {
          data[k] = await redactedBody(v);
          changed = true;
        }
      }
      if (!changed) continue;
      await _db.customStatement(
        'UPDATE sync_base SET data = ? WHERE table_name = ? '
        "AND row_key = json_object('id', ?)",
        [jsonEncode(data), 'note_comments', id],
      );
    }
  }

  /// Replaces the plain body in the sync merge base of these rows (the
  /// version from before this device's unsynced edits, kept so a
  /// concurrent edit can be merged) with its fingerprint. Deleting the base
  /// instead would skip the merge on the next sync — and then an older
  /// lock could lose to another device's newer plain edit, unlocking the
  /// note. With the fingerprint the merge still sees what changed, and the
  /// lock wins (`features/sync/merge.dart`).
  Future<void> _redactMergeBase(String table, List<String> ids) async {
    for (final id in ids) {
      final rows = await _db
          .customSelect(
            'SELECT data FROM sync_base WHERE table_name = ? '
            "AND row_key = json_object('id', ?)",
            variables: [Variable.withString(table), Variable.withString(id)],
          )
          .get();
      if (rows.isEmpty) continue;
      final data = jsonDecode(rows.single.read<String>('data'));
      if (data is! Map<String, dynamic>) continue;
      final content = data['content'];
      if (content is! String ||
          isLockedContent(content) ||
          isRedactedBase(content)) {
        continue;
      }
      data['content'] = await redactedBody(content);
      await _db.customStatement(
        'UPDATE sync_base SET data = ? WHERE table_name = ? '
        "AND row_key = json_object('id', ?)",
        [jsonEncode(data), table, id],
      );
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _keys.clear();
    super.dispose();
  }

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}

/// The app's one lock service. Locks when the app goes to the background
/// (phones, tablets) and after [NoteLockService.autoLockAfter] idle.
final noteLockServiceProvider = ChangeNotifierProvider<NoteLockService>((ref) {
  final service = NoteLockService(
    ref.watch(databaseProvider),
    biometrics: ref.watch(biometricKeyStoreProvider),
  );
  // Plain (non-widget) tests read providers that depend on this one and
  // have no binding to listen to; there's no app to pause there anyway.
  try {
    final lifecycle = AppLifecycleListener(onPause: service.lockNow);
    ref.onDispose(lifecycle.dispose);
  } on FlutterError {
    // No WidgetsBinding.
  }
  return service;
});

/// Whether a notes password exists (live; the Lock menu items and the
/// Settings row depend on it).
final hasNotesPasswordProvider = StreamProvider<bool>(
  (ref) => ref.watch(noteLockServiceProvider).watchHasPassword(),
);
