import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final papersListProvider = StreamProvider.autoDispose<List<Paper>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.papers,
  )..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).watch();
});

/// Current text typed into the Library search field.
final librarySearchProvider = StateProvider.autoDispose<String>((ref) => '');

final filteredPapersProvider = Provider.autoDispose<AsyncValue<List<Paper>>>((
  ref,
) {
  final query = ref.watch(librarySearchProvider).trim().toLowerCase();
  final papersAsync = ref.watch(papersListProvider);
  if (query.isEmpty) return papersAsync;
  return papersAsync.whenData(
    (papers) => papers
        .where(
          (p) =>
              p.title.toLowerCase().contains(query) ||
              p.authors.toLowerCase().contains(query),
        )
        .toList(),
  );
});

final attachmentsForPaperProvider = StreamProvider.autoDispose
    .family<List<Attachment>, int>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.attachments,
      )..where((a) => a.paperId.equals(paperId))).watch();
    });

final paperByIdProvider = StreamProvider.autoDispose.family<Paper?, int>((
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
    .family<List<Note>, int>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.notes).join([
              innerJoin(
                db.notePaperRefs,
                db.notePaperRefs.noteId.equalsExp(db.notes.id),
              ),
            ])
            ..where(db.notePaperRefs.paperId.equals(paperId));
      return query.watch().map(
        (rows) => rows.map((row) => row.readTable(db.notes)).toList(),
      );
    });
