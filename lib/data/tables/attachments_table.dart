import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'notes_table.dart';
import 'papers_table.dart';

/// Types of external material that can be attached to a note or a paper,
/// e.g. a NotebookLM-style podcast summary, an image, a link, or a file.
enum AttachmentType { pdf, podcast, image, link, file }

/// An attachment belongs to a note, a paper, or both — at least one of
/// [noteId] / [paperId] must be set. Enforced in the DAO layer, since a
/// portable CHECK across two nullable FKs isn't worth the SQL here.
/// Primary key is a client-generated UUID (see notes_table.dart for why).
class Attachments extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  TextColumn get noteId =>
      text().nullable().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get paperId =>
      text().nullable().references(Papers, #id, onDelete: KeyAction.cascade)();

  TextColumn get type => textEnum<AttachmentType>()();
  TextColumn get title => text().nullable()();

  /// Local file path, for imported files (PDFs, images, audio).
  TextColumn get path => text().nullable()();

  /// External link, for things like a NotebookLM podcast share URL.
  TextColumn get url => text().nullable()();

  /// Object key of the file in cloud storage once uploaded (synced, unlike
  /// [path], which only means something on this device).
  TextColumn get storageKey => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
