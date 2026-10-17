import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'papers_table.dart';
import 'projects_table.dart';

/// A column of a project's synthesis matrix — a theme the reader is
/// comparing papers on (method, sample, findings…).
class MatrixColumns extends Table {
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();
  TextColumn get projectId =>
      text().references(Projects, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();

  /// Left-to-right order.
  IntColumn get position => integer().withDefault(const Constant(0))();

  /// When set, the column shows a paper's study detail (`species`,
  /// `brain_regions`, `techniques`, `sample_size`, `paradigm`) instead of
  /// its own cells, and editing a cell edits the paper (schema v15).
  TextColumn get paperField => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

/// What one paper says about one theme. A missing row is an empty cell.
class MatrixCells extends Table {
  TextColumn get columnId =>
      text().references(MatrixColumns, #id, onDelete: KeyAction.cascade)();
  TextColumn get paperId =>
      text().references(Papers, #id, onDelete: KeyAction.cascade)();
  TextColumn get text_ =>
      text().named('text').withDefault(const Constant(''))();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {columnId, paperId};
}
