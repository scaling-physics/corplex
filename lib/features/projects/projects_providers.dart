import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final projectsListProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.projects,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
});

/// Projects a paper belongs to.
final projectsForPaperProvider = StreamProvider.autoDispose
    .family<List<Project>, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.projects).join([
              innerJoin(
                db.projectPapers,
                db.projectPapers.projectId.equalsExp(db.projects.id),
              ),
            ])
            ..where(db.projectPapers.paperId.equals(paperId))
            ..orderBy([OrderingTerm.asc(db.projects.name)]);
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.projects)).toList(),
      );
    });

/// Projects a note belongs to.
final projectsForNoteProvider = StreamProvider.autoDispose
    .family<List<Project>, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.projects).join([
              innerJoin(
                db.projectNotes,
                db.projectNotes.projectId.equalsExp(db.projects.id),
              ),
            ])
            ..where(db.projectNotes.noteId.equals(noteId))
            ..orderBy([OrderingTerm.asc(db.projects.name)]);
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.projects)).toList(),
      );
    });

/// Paper ids in each project, for filtering the Library.
final projectPaperIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.projectPapers)
            ..where((r) => r.projectId.equals(projectId)))
          .watch()
          .map((rows) => {for (final r in rows) r.paperId});
    });

/// Note ids in a project, for filtering the Notes list.
final projectNoteIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, projectId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.projectNotes)
            ..where((r) => r.projectId.equals(projectId)))
          .watch()
          .map((rows) => {for (final r in rows) r.noteId});
    });

/// Creates a project, or returns the existing one with this name (ignoring
/// case), so typing "Thesis" twice never makes two.
Future<String> findOrCreateProject(AppDatabase db, String name) async {
  final clean = name.trim();
  final existing =
      await (db.select(db.projects)
            ..where((p) => p.name.lower().equals(clean.toLowerCase())))
          .getSingleOrNull();
  if (existing != null) return existing.id;
  final id = const Uuid().v4();
  await db
      .into(db.projects)
      .insert(ProjectsCompanion.insert(id: Value(id), name: clean));
  return id;
}

Future<void> renameProject(AppDatabase db, String id, String name) =>
    (db.update(db.projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(name: Value(name.trim())),
    );

/// Deleting a project only removes the grouping — its papers and notes
/// stay (the join rows cascade away).
Future<void> deleteProject(AppDatabase db, String id) =>
    (db.delete(db.projects)..where((p) => p.id.equals(id))).go();

Future<void> addPaperToProject(
  AppDatabase db, {
  required String projectId,
  required String paperId,
}) => db
    .into(db.projectPapers)
    .insert(
      ProjectPapersCompanion.insert(projectId: projectId, paperId: paperId),
      mode: InsertMode.insertOrIgnore,
    );

Future<void> removePaperFromProject(
  AppDatabase db, {
  required String projectId,
  required String paperId,
}) =>
    (db.delete(db.projectPapers)..where(
          (r) => r.projectId.equals(projectId) & r.paperId.equals(paperId),
        ))
        .go();

Future<void> addNoteToProject(
  AppDatabase db, {
  required String projectId,
  required String noteId,
}) => db
    .into(db.projectNotes)
    .insert(
      ProjectNotesCompanion.insert(projectId: projectId, noteId: noteId),
      mode: InsertMode.insertOrIgnore,
    );

Future<void> removeNoteFromProject(
  AppDatabase db, {
  required String projectId,
  required String noteId,
}) => (db.delete(
  db.projectNotes,
)..where((r) => r.projectId.equals(projectId) & r.noteId.equals(noteId))).go();
