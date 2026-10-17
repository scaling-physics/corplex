import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// The notes password, as wrapped keys (schema v17, synced). Locked notes
/// are encrypted with a random 256-bit notes key; a row here holds that
/// key encrypted ("wrapped") under a key derived from the notes password,
/// so any device that knows the password can unlock the notes, and the
/// sync server never can. Nothing here is the password or the key itself.
///
/// Normally one row. A forgotten password is "reset" by adding a new row
/// (new key, new password): notes locked under the old one stay locked
/// until its password is remembered (`features/lock/`).
@DataClassName('NoteKeyRow')
class NoteKeys extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// Key derivation: `pbkdf2-sha256`, its iteration count and salt
  /// (base64). Stored per row so the cost can be raised later.
  TextColumn get kdf => text().withDefault(const Constant('pbkdf2-sha256'))();
  IntColumn get iterations => integer()();
  TextColumn get salt => text()();

  /// The notes key, AES-256-GCM encrypted under the password-derived key:
  /// base64 of nonce (12 bytes) + ciphertext + tag (16 bytes).
  TextColumn get wrappedKey => text()();

  /// An optional reminder the reader wrote; stored in the clear.
  TextColumn get hint => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
