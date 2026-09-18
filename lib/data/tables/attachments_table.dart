import 'package:drift/drift.dart';

import 'notes_table.dart';
import 'papers_table.dart';

/// Types of external material that can be attached to a note or a paper,
/// e.g. a NotebookLM-style podcast summary, an image, a link, or a file.
enum AttachmentType { pdf, podcast, image, link, file }

/// An attachment belongs to a note, a paper, or both — at least one of
/// [noteId] / [paperId] must be set. Enforced in the DAO layer, since a
/// portable CHECK across two nullable FKs isn't worth the SQL here.
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get noteId =>
      integer().nullable().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get paperId => integer()
      .nullable()
      .references(Papers, #id, onDelete: KeyAction.cascade)();

  TextColumn get type => textEnum<AttachmentType>()();
  TextColumn get title => text().nullable()();

  /// Local file path, for imported files (PDFs, images, audio).
  TextColumn get path => text().nullable()();

  /// External link, for things like a NotebookLM podcast share URL.
  TextColumn get url => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
