import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

/// What the Notes list is currently narrowed to — a single dimension at a
/// time (folder or tag, never both) to keep the filter UI a simple chip row
/// rather than a combinable filter builder.
sealed class NotesFilter {
  const NotesFilter();
}

class AllNotes extends NotesFilter {
  const AllNotes();
}

class FolderFilter extends NotesFilter {
  const FolderFilter(this.folderId);
  final String folderId;
}

class TagFilter extends NotesFilter {
  const TagFilter(this.tagId);
  final String tagId;
}

class ProjectFilter extends NotesFilter {
  const ProjectFilter(this.projectId);
  final String projectId;
}

final notesFilterProvider = StateProvider.autoDispose<NotesFilter>(
  (ref) => const AllNotes(),
);

final visibleNotesProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  final filter = ref.watch(notesFilterProvider);

  switch (filter) {
    case AllNotes():
      return (db.select(
        db.notes,
      )..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])).watch();
    case FolderFilter(:final folderId):
      return (db.select(db.notes)
            ..where((n) => n.folderId.equals(folderId))
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .watch();
    case ProjectFilter(:final projectId):
      final query =
          db.select(db.notes).join([
              innerJoin(
                db.projectNotes,
                db.projectNotes.noteId.equalsExp(db.notes.id),
              ),
            ])
            ..where(db.projectNotes.projectId.equals(projectId))
            ..orderBy([OrderingTerm.desc(db.notes.updatedAt)]);
      return query.watch().map(
        (rows) => rows.map((row) => row.readTable(db.notes)).toList(),
      );
    case TagFilter(:final tagId):
      final query =
          db.select(db.notes).join([
              innerJoin(db.noteTags, db.noteTags.noteId.equalsExp(db.notes.id)),
            ])
            ..where(db.noteTags.tagId.equals(tagId))
            ..orderBy([OrderingTerm.desc(db.notes.updatedAt)]);
      return query.watch().map(
        (rows) => rows.map((row) => row.readTable(db.notes)).toList(),
      );
  }
});
