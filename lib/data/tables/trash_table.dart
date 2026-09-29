import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// What was deleted, kept for a while so it can be restored.
enum TrashKind { note, paper }

/// A deleted note or paper, snapshotted with everything that went with it
/// (attachments, links, highlights…) as JSON so it can be put back exactly.
///
/// Local to this device and deliberately *not* synced: a delete still
/// syncs as a delete, and restoring re-creates the rows (which then sync
/// as new edits). Files on disk are kept until the item is purged.
class TrashItems extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get kind => textEnum<TrashKind>()();

  /// The deleted row's id (a note or paper id).
  TextColumn get itemId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get payloadJson => text()();
  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
