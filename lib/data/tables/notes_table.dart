import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'folders_table.dart';

/// A single note. Content is stored as a JSON-encoded rich document so a
/// note can mix text, images, and pen strokes in one flow.
///
/// The primary key is a client-generated UUID rather than an autoincrement
/// integer: once notes can be created offline on multiple devices and
/// synced later, locally-assigned integer IDs from two devices could
/// collide, while a UUID generated at creation time never does.
class Notes extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// A note belongs to at most one folder; null means unfiled. Deleting a
  /// folder unfiles its notes rather than deleting them.
  TextColumn get folderId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();

  /// Pinned notes sit at the top of the Notes list (schema v18, synced).
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// The day this note is the daily note of, as `YYYY-MM-DD` in local time
  /// (schema v22, synced); null for every other note. Two devices offline
  /// on the same day can each make one, so lookups take the oldest.
  TextColumn get dailyDate => text().nullable()();

  /// Other names the note can be linked and found by, stored `a; b` like
  /// the study-detail lists (schema v22, synced).
  TextColumn get aliases => text().nullable()();

  /// A template: kept out of the ordinary notes lists and offered when
  /// making a note or inserting one (schema v22, synced).
  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
