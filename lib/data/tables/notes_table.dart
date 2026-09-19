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

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
