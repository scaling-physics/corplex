import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../library/authors.dart';
import '../library/study_details.dart';

/// The synthesis matrix of a project: its papers down the side, the themes
/// the reader is comparing across the top, and what each paper says about
/// each theme in the cells. It only exists once the reader adds a column.
const defaultMatrixColumns = ['Method', 'Sample', 'Findings'];

Future<String> addMatrixColumn(
  AppDatabase db,
  String projectId,
  String name, {
  StudyField? field,
}) async {
  final last =
      await (db.select(db.matrixColumns)
            ..where((c) => c.projectId.equals(projectId))
            ..orderBy([(c) => OrderingTerm.desc(c.position)])
            ..limit(1))
          .getSingleOrNull();
  final id = const Uuid().v4();
  await db
      .into(db.matrixColumns)
      .insert(
        MatrixColumnsCompanion.insert(
          id: Value(id),
          projectId: projectId,
          name: name.trim(),
          paperField: Value(field?.key),
          position: Value((last?.position ?? -1) + 1),
        ),
      );
  return id;
}

Future<void> addDefaultMatrixColumns(AppDatabase db, String projectId) async {
  for (final name in defaultMatrixColumns) {
    await addMatrixColumn(db, projectId, name);
  }
}

/// Adds the study-detail columns the project doesn't have yet, in order.
/// Returns how many were added.
Future<int> addStudyColumns(AppDatabase db, String projectId) async {
  final existing =
      (await (db.select(
            db.matrixColumns,
          )..where((c) => c.projectId.equals(projectId))).get())
          .map((c) => c.paperField)
          .toSet();
  var added = 0;
  for (final f in StudyField.values) {
    if (existing.contains(f.key)) continue;
    await addMatrixColumn(db, projectId, f.label, field: f);
    added++;
  }
  return added;
}

/// What a cell shows: a bound column reads the paper's study detail (lists
/// joined with ", "), any other column its `matrix_cells` text.
String matrixCellText(
  MatrixColumn column,
  Paper paper,
  Map<String, String> cells,
) {
  final field = StudyField.byKey(column.paperField);
  if (field == null) return cells['${column.id}|${paper.id}'] ?? '';
  return studyValues(paper, field).join(', ');
}

Future<void> renameMatrixColumn(AppDatabase db, String columnId, String name) =>
    (db.update(db.matrixColumns)..where((c) => c.id.equals(columnId))).write(
      MatrixColumnsCompanion(name: Value(name.trim())),
    );

/// Removes the column and (by cascade) everything written under it. A
/// column bound to study details has no cells; papers are never touched.
Future<void> deleteMatrixColumn(AppDatabase db, String columnId) =>
    (db.delete(db.matrixColumns)..where((c) => c.id.equals(columnId))).go();

/// Sets a cell; empty text removes the row so blank cells cost nothing.
Future<void> setMatrixCell(
  AppDatabase db,
  String columnId,
  String paperId,
  String text,
) async {
  if (text.trim().isEmpty) {
    await (db.delete(db.matrixCells)..where(
          (c) => c.columnId.equals(columnId) & c.paperId.equals(paperId),
        ))
        .go();
    return;
  }
  await db
      .into(db.matrixCells)
      .insertOnConflictUpdate(
        MatrixCellsCompanion.insert(
          columnId: columnId,
          paperId: paperId,
          text_: Value(text.trim()),
        ),
      );
}

final matrixColumnsProvider = StreamProvider.autoDispose
    .family<List<MatrixColumn>, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.matrixColumns)
            ..where((c) => c.projectId.equals(projectId))
            ..orderBy([
              (c) => OrderingTerm.asc(c.position),
              (c) => OrderingTerm.asc(c.createdAt),
            ]))
          .watch();
    });

/// Every cell of a project's matrix, keyed `columnId|paperId`.
final matrixCellsProvider = StreamProvider.autoDispose
    .family<Map<String, String>, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.matrixCells).join([
        innerJoin(
          db.matrixColumns,
          db.matrixColumns.id.equalsExp(db.matrixCells.columnId),
        ),
      ])..where(db.matrixColumns.projectId.equals(projectId));
      return query.watch().map(
        (rows) => {
          for (final r in rows)
            '${r.readTable(db.matrixCells).columnId}|'
                '${r.readTable(db.matrixCells).paperId}': r
                .readTable(db.matrixCells)
                .text_,
        },
      );
    });

/// The papers in a project, oldest first (stable row order).
final projectPapersProvider = StreamProvider.autoDispose
    .family<List<Paper>, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.papers).join([
              innerJoin(
                db.projectPapers,
                db.projectPapers.paperId.equalsExp(db.papers.id),
              ),
            ])
            ..where(db.projectPapers.projectId.equals(projectId))
            ..orderBy([OrderingTerm.asc(db.papers.createdAt)]);
      return query.watch().map(
        (rows) => [for (final r in rows) r.readTable(db.papers)],
      );
    });

/// "Vaswani et al. 2017", the short label for a paper's row.
String paperShortLabel(Paper paper) {
  final authors = parseAuthors(paper.authors).authors;
  final who = authors.isEmpty
      ? paper.title
      : authors.length > 2
      ? '${authors.first.family} et al.'
      : authors.map((a) => a.family).join(' & ');
  return paper.year == null ? who : '$who ${paper.year}';
}

/// The matrix as a Markdown table, for pasting into a note or draft.
String matrixToMarkdown(
  List<MatrixColumn> columns,
  List<Paper> papers,
  Map<String, String> cells,
) {
  String cell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');
  final header = ['Paper', ...columns.map((c) => cell(c.name))];
  final lines = [
    '| ${header.join(' | ')} |',
    '| ${header.map((_) => '---').join(' | ')} |',
    for (final p in papers)
      '| ${[cell(paperShortLabel(p)), for (final c in columns) cell(matrixCellText(c, p, cells))].join(' | ')} |',
  ];
  return '${lines.join('\n')}\n';
}
