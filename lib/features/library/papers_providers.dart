import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/papers_table.dart';
import '../projects/projects_providers.dart';

final papersListProvider = StreamProvider.autoDispose<List<Paper>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).watch();
});

/// Current text typed into the Library search field.
final librarySearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Narrows the Library to one reading status (null = everything). The
/// filter row only appears once a paper has been given a status.
final libraryStatusFilterProvider = StateProvider.autoDispose<ReadingStatus?>(
  (ref) => null,
);

/// Narrows the Library to one project (null = everything).
final libraryProjectFilterProvider = StateProvider.autoDispose<String?>(
  (ref) => null,
);

final filteredPapersProvider = Provider.autoDispose<AsyncValue<List<Paper>>>((
  ref,
) {
  final query = ref.watch(librarySearchProvider).trim().toLowerCase();
  final status = ref.watch(libraryStatusFilterProvider);
  final projectId = ref.watch(libraryProjectFilterProvider);
  final inProject = projectId == null
      ? null
      : ref.watch(projectPaperIdsProvider(projectId)).value ?? const <String>{};
  final papersAsync = ref.watch(papersListProvider);
  if (query.isEmpty && status == null && inProject == null) return papersAsync;
  return papersAsync.whenData(
    (papers) => papers
        .where(
          (p) =>
              (status == null || p.readingStatus == status) &&
              (inProject == null || inProject.contains(p.id)) &&
              (query.isEmpty ||
                  p.title.toLowerCase().contains(query) ||
                  p.authors.toLowerCase().contains(query) ||
                  (p.venue ?? '').toLowerCase().contains(query) ||
                  (p.doi ?? '').toLowerCase().contains(query)),
        )
        .toList(),
  );
});

final attachmentsForPaperProvider = StreamProvider.autoDispose
    .family<List<Attachment>, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.attachments,
      )..where((a) => a.paperId.equals(paperId))).watch();
    });

final paperByIdProvider = StreamProvider.autoDispose.family<Paper?, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..where((p) => p.id.equals(id))).watchSingleOrNull();
});

/// Every note that links to this paper, via NotePaperRefs.
final notesForPaperProvider = StreamProvider.autoDispose
    .family<List<Note>, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.notes).join([
        innerJoin(
          db.notePaperRefs,
          db.notePaperRefs.noteId.equalsExp(db.notes.id),
        ),
      ])..where(db.notePaperRefs.paperId.equals(paperId));
      return query.watch().map(
        (rows) => rows.map((row) => row.readTable(db.notes)).toList(),
      );
    });

/// Sets (or, with null, clears) where a paper is in the reader's queue.
Future<void> setReadingStatus(
  AppDatabase db,
  String paperId,
  ReadingStatus? status,
) => (db.update(db.papers)..where((p) => p.id.equals(paperId))).write(
  PapersCompanion(readingStatus: Value(status)),
);
