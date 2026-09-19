import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final notesListProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])).watch();
});

final noteByIdProvider = StreamProvider.autoDispose.family<Note?, String>((
  ref,
  id,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).watchSingleOrNull();
});
