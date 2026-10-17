import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartPbkdf2;
import 'package:cryptography_flutter/cryptography_flutter.dart'
    show FlutterPbkdf2;

/// Locked notes: the cryptography, with no Flutter, database or UI in it.
///
/// * A **notes key** is 32 random bytes. Locked note bodies (and their
///   saved versions) are AES-256-GCM encrypted with it, bound to the note's
///   id as associated data, so a body can't be moved onto another note.
/// * The **notes password** never touches a note: PBKDF2-HMAC-SHA256
///   (salted, [defaultIterations]) turns it into a key-encryption key that
///   *wraps* the notes key. Only the wrapped key is stored and synced
///   (`NoteKeys`). A wrong password fails GCM's tag check when unwrapping,
///   which is how a password is checked.
/// * A locked body is stored as an **envelope** string in the same
///   `content` column: `corplex-locked:v1:<keyId>:<base64url(nonce|ct|tag)>`.
///   Everything that reads `content` must check [isLockedContent] first.

/// The start of every locked body. Note content is otherwise Quill Delta
/// JSON (or, for very old notes, plain text), never this.
const lockedPrefix = 'corplex-locked:v1:';

bool isLockedContent(String content) => content.startsWith(lockedPrefix);

/// A plain body redacted to its fingerprint: what the sync merge base
/// keeps for a note once it's locked (`sync_base`), so the merge can still
/// tell whether the other device changed the body since — compare
/// [redactedBody] of its plain body — without plain text staying behind.
const redactedBasePrefix = 'corplex-base-sha256:';

bool isRedactedBase(String content) => content.startsWith(redactedBasePrefix);

/// [plain] as `corplex-base-sha256:<hex>`.
Future<String> redactedBody(String plain) async {
  final hash = await Sha256().hash(utf8.encode(plain));
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0'));
  return '$redactedBasePrefix${hex.join()}';
}

/// The id of the notes key (`NoteKeys.id`) a locked body was encrypted
/// with, or null if [content] isn't a locked body.
String? lockedKeyId(String content) {
  if (!isLockedContent(content)) return null;
  final rest = content.substring(lockedPrefix.length);
  final colon = rest.indexOf(':');
  return colon <= 0 ? null : rest.substring(0, colon);
}

/// A notes key in memory, with the id of the `NoteKeys` row it came from.
class NoteKey {
  const NoteKey(this.id, this.bytes);

  final String id;
  final List<int> bytes;
}

/// Wrong password, a damaged envelope, or the wrong key.
class NoteDecryptException implements Exception {
  const NoteDecryptException(this.message);

  final String message;

  @override
  String toString() => 'NoteDecryptException: $message';
}

class NoteCrypto {
  NoteCrypto({this.iterations = defaultIterations, Random? random})
    : _random = random ?? Random.secure();

  /// OWASP's recommendation for PBKDF2-HMAC-SHA256 (2023). About 1.8 s in
  /// pure Dart on an M-series Mac; it runs once per unlock, off the UI
  /// isolate (natively on Android), and never when unlocking with
  /// biometrics.
  static const defaultIterations = 600000;

  /// The derivation recorded in `NoteKeys.kdf`: PBKDF2-HMAC-SHA256 over the
  /// password's UTF-8 bytes, base64-encoded ([kdfInput]).
  static const kdfName = 'pbkdf2-sha256-b64utf8';

  /// What PBKDF2 is given instead of the password itself: base64 of its
  /// UTF-8 bytes. Android derives natively (javax.crypto), which may turn
  /// non-ASCII characters into bytes differently from Dart; an ASCII-only
  /// input makes every platform derive the same key from "Grüße 🔒", so a
  /// password set on a Mac also works on a phone.
  static String kdfInput(String password) =>
      base64.encode(utf8.encode(password));

  /// For new keys; existing keys keep the count stored with them.
  final int iterations;
  final Random _random;

  static final _aes = AesGcm.with256bits();
  static const _wrapAad = 'corplex-notes-key';

  List<int> randomBytes(int n) => [
    for (var i = 0; i < n; i++) _random.nextInt(256),
  ];

  /// A fresh notes key (32 bytes) and a salt (16 bytes) for its password.
  List<int> newNoteKey() => randomBytes(32);
  List<int> newSalt() => randomBytes(16);

  /// The key-encryption key for [password]. Slow on purpose. On Android
  /// it runs natively (cryptography_flutter: a platform call, so the UI
  /// isn't blocked); elsewhere pure Dart on a background isolate. [inline]
  /// runs pure Dart on the calling isolate (tests: isolates don't run under
  /// the fake clock, and there are no plugins).
  Future<List<int>> deriveKek(
    String password,
    List<int> salt,
    int iterations, {
    bool inline = false,
  }) async {
    final input = kdfInput(password);
    Future<List<int>> derive() async {
      final key = await DartPbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: input, nonce: salt);
      return key.extractBytes();
    }

    if (inline) return derive();
    if (Platform.isAndroid) {
      try {
        final key = await FlutterPbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: iterations,
          bits: 256,
        ).deriveKeyFromPassword(password: input, nonce: salt);
        return await key.extractBytes();
      } catch (_) {
        // No plugin or no native support: same result in pure Dart.
      }
    }
    return Isolate.run(derive);
  }

  /// [noteKey] encrypted under [kek]: base64 of nonce + ciphertext + tag.
  Future<String> wrap(List<int> kek, List<int> noteKey) async {
    final box = await _aes.encrypt(
      noteKey,
      secretKey: SecretKey(kek),
      nonce: randomBytes(12),
      aad: utf8.encode(_wrapAad),
    );
    return base64.encode(box.concatenation());
  }

  /// The notes key inside [wrapped], or null if [kek] is wrong (that is,
  /// the password was wrong) or the data is damaged.
  Future<List<int>?> unwrap(List<int> kek, String wrapped) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(wrapped),
        nonceLength: 12,
        macLength: 16,
      );
      return await _aes.decrypt(
        box,
        secretKey: SecretKey(kek),
        aad: utf8.encode(_wrapAad),
      );
    } on SecretBoxAuthenticationError {
      return null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// [plaintext] (a note body as stored: Delta JSON) locked for note
  /// [noteId] with [key], as an envelope.
  Future<String> encrypt(NoteKey key, String noteId, String plaintext) async {
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key.bytes),
      nonce: randomBytes(12),
      aad: _noteAad(noteId),
    );
    return '$lockedPrefix${key.id}:${base64Url.encode(box.concatenation())}';
  }

  /// The body inside [envelope], which must have been locked for [noteId]
  /// with [key]. Throws [NoteDecryptException] otherwise.
  Future<String> decrypt(NoteKey key, String noteId, String envelope) async {
    if (lockedKeyId(envelope) != key.id) {
      throw const NoteDecryptException('locked with a different key');
    }
    final payload = envelope.substring(lockedPrefix.length + key.id.length + 1);
    try {
      final box = SecretBox.fromConcatenation(
        base64Url.decode(payload),
        nonceLength: 12,
        macLength: 16,
      );
      final clear = await _aes.decrypt(
        box,
        secretKey: SecretKey(key.bytes),
        aad: _noteAad(noteId),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const NoteDecryptException('wrong key or damaged note');
    } on FormatException {
      throw const NoteDecryptException('damaged note');
    } on ArgumentError {
      throw const NoteDecryptException('damaged note');
    }
  }

  static List<int> _noteAad(String noteId) =>
      utf8.encode('corplex-note:$noteId');
}
