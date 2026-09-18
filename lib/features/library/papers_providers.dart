import 'package:drift/drift.dart' show OrderingTerm;
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
