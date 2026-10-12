import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'notes_table.dart';
import 'papers_table.dart';

enum ChapterStatus { outline, draft, withSupervisor, revised, finished }

/// A named group of papers and notes — one per literature review, thesis
/// chapter or paper being written. A paper or note can be in several.
class Projects extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// The submission date, if the writer set one.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Bumped on every edit; sync uses it for last-write-wins (see sync_schema.dart).
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

/// Join table: a paper belongs to a project.
class ProjectPapers extends Table {
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {projectId, paperId};
}

/// Join table: a note belongs to a project.
class ProjectNotes extends Table {
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// Place among the project's chapters. Null until the writer first
  /// reorders; unplaced rows follow the placed ones, oldest note first.
  IntColumn get position => integer().nullable()();

  /// How far the chapter has got; null = no status.
  TextColumn get status => textEnum<ChapterStatus>().nullable()();

  /// Words the chapter should reach, if set.
  IntColumn get wordTarget => integer().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {projectId, noteId};
}
