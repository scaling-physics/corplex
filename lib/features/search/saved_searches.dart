import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// drift's name for a `SavedSearches` row (it singularises badly).
typedef SavedSearchEntry = SavedSearche;

/// Saved searches, in the order the reader sees them: by position, then
/// (while nobody has reordered) by creation.
final savedSearchesProvider =
    StreamProvider.autoDispose<List<SavedSearchEntry>>((ref) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.savedSearches)..orderBy([
            (s) => OrderingTerm(expression: s.position, nulls: NullsOrder.last),
            (s) => OrderingTerm.asc(s.createdAt),
            (s) => OrderingTerm.asc(s.name),
          ]))
          .watch();
    });

/// A search the Mac sidebar asks the toolbar field to run; `HomeShell`
/// takes it, puts it in the field and clears this.
final savedSearchRunRequestProvider = StateProvider<String?>((ref) => null);

/// Keeps [query] under [name] (the query itself when the name is blank).
/// Returns the new id.
Future<String> createSavedSearch(
  AppDatabase db, {
  required String name,
  required String query,
}) async {
  final id = const Uuid().v4();
  final trimmedQuery = query.trim();
  final trimmedName = name.trim();
  await db
      .into(db.savedSearches)
      .insert(
        SavedSearchesCompanion.insert(
          id: Value(id),
          name: trimmedName.isEmpty ? trimmedQuery : trimmedName,
          query: trimmedQuery,
        ),
      );
  return id;
}

Future<void> renameSavedSearch(AppDatabase db, String id, String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  await (db.update(db.savedSearches)..where((s) => s.id.equals(id))).write(
    SavedSearchesCompanion(
      name: Value(trimmed),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

Future<void> deleteSavedSearch(AppDatabase db, String id) =>
    (db.delete(db.savedSearches)..where((s) => s.id.equals(id))).go();

/// Puts a deleted search back (Undo), where it was.
Future<void> restoreSavedSearch(AppDatabase db, SavedSearchEntry s) => db
    .into(db.savedSearches)
    .insertOnConflictUpdate(
      SavedSearchesCompanion.insert(
        id: Value(s.id),
        name: s.name,
        query: s.query,
        position: Value(s.position),
        createdAt: Value(s.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
