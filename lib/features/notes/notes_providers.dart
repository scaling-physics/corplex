import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_crypto.dart' show isLockedContent;
import 'note_content.dart';

/// A note as the Notes list needs it: no body, just the stored preview (see
/// `NotePreviews`). The full [Note] is loaded only when one is opened.
class NoteListItem {
  const NoteListItem({
    required this.id,
    required this.title,
    required this.folderId,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
    required this.preview,
    required this.locked,
  });

  final String id;
  final String title;
  final String? folderId;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// One line of the body's text; empty for a locked note.
  final String preview;
  final bool locked;

  NoteListItem withPreview(String preview, bool locked) => NoteListItem(
    id: id,
    title: title,
    folderId: folderId,
    pinned: pinned,
    createdAt: createdAt,
    updatedAt: updatedAt,
    preview: preview,
    locked: locked,
  );

  @override
  bool operator ==(Object other) =>
      other is NoteListItem &&
      other.id == id &&
      other.title == title &&
      other.folderId == folderId &&
      other.pinned == pinned &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.preview == preview &&
      other.locked == locked;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    folderId,
    pinned,
    createdAt,
    updatedAt,
    preview,
    locked,
  );
}

/// The longest preview stored. The list shows two lines at most.
const notePreviewLength = 300;

/// How many missing previews one pass computes. A first load of a big
/// library is spread over passes (each emits, then yields) instead of
/// decoding thousands of bodies before the first frame.
const previewsPerPass = 60;

/// The text stored for a note body: its [notePlainTextPreview] logic without
/// the LRU (a bulk fill would only churn it), cut to [notePreviewLength].
String storedPreviewOf(String content) {
  final text = previewOfDocument(decodeNoteContent(content));
  if (text.length <= notePreviewLength) return text;
  var cut = text.substring(0, notePreviewLength);
  // Don't end on half a surrogate pair.
  final last = cut.codeUnitAt(cut.length - 1);
  if (last >= 0xD800 && last <= 0xDBFF) cut = cut.substring(0, cut.length - 1);
  return cut;
}

/// The Notes list rows for [filter], pinned first then newest edit, reading
/// no note bodies except those whose preview is missing (new, edited, or
/// never shown); those are computed, stored and emitted in the same pass.
Stream<List<NoteListItem>> watchNoteList(AppDatabase db, NotesFilter filter) {
  final (join, where, variables) = switch (filter) {
    AllNotes() => ('', '', <Variable>[]),
    FolderFilter(:final folderId) => (
      '',
      'WHERE n.folder_id = ?',
      [Variable.withString(folderId)],
    ),
    ProjectFilter(:final projectId) => (
      'JOIN project_notes f ON f.note_id = n.id',
      'WHERE f.project_id = ?',
      [Variable.withString(projectId)],
    ),
    TagFilter(:final tagId) => (
      'JOIN note_tags f ON f.note_id = n.id',
      'WHERE f.tag_id = ?',
      [Variable.withString(tagId)],
    ),
  };
  final query = db.customSelect(
    'SELECT n.id, n.title, n.folder_id, n.pinned, n.created_at, n.updated_at, '
    'p.preview AS preview, p.locked AS locked, '
    '(p.note_id IS NOT NULL) AS has_preview '
    'FROM notes n LEFT JOIN note_previews p ON p.note_id = n.id '
    '$join $where ORDER BY n.pinned DESC, n.updated_at DESC',
    variables: variables,
    readsFrom: {
      db.notes,
      db.notePreviews,
      if (filter is ProjectFilter) db.projectNotes,
      if (filter is TagFilter) db.noteTags,
    },
  );

  List<NoteListItem>? last;
  return query
      .watch()
      .asyncMap((rows) async {
        final items = <NoteListItem>[];
        final stale = <int>[];
        for (final r in rows) {
          if (!r.read<bool>('has_preview')) stale.add(items.length);
          items.add(
            NoteListItem(
              id: r.read<String>('id'),
              title: r.read<String>('title'),
              folderId: r.read<String?>('folder_id'),
              pinned: r.read<bool>('pinned'),
              createdAt: r.read<DateTime>('created_at'),
              updatedAt: r.read<DateTime>('updated_at'),
              preview: r.read<String?>('preview') ?? '',
              locked: r.read<bool?>('locked') ?? false,
            ),
          );
        }
        if (stale.isEmpty) return items;
        final pass = stale.take(previewsPerPass).toList();
        await _fillPreviews(db, items, pass);
        if (stale.length > pass.length) {
          // More to do: wake this query again after the list is shown.
          Future(() => db.notifyUpdates({const TableUpdate('note_previews')}));
        }
        return items;
      })
      .where((items) {
        // The write above re-wakes the query (and so does a trigger-deleted
        // preview): don't re-emit what the screen already has.
        final same =
            last != null &&
            last!.length == items.length &&
            Iterable<int>.generate(items.length)
                .every((i) => last![i] == items[i]);
        last = items;
        return !same;
      });
}

/// Computes and stores the previews of `items[indexes]`, updating the items
/// in place. A locked body stores `locked` and an empty preview — never its
/// text. The insert is conditional on the body being the one that was read,
/// so a concurrent edit (whose trigger found nothing to delete yet) can't be
/// followed by a stale row; and it uses `customStatement`, which doesn't
/// notify, so storing previews never re-triggers the list.
Future<void> _fillPreviews(
  AppDatabase db,
  List<NoteListItem> items,
  List<int> indexes,
) async {
  final byId = {for (final i in indexes) items[i].id: i};
  final bodies = <String, String>{};
  final ids = byId.keys.toList();
  for (var start = 0; start < ids.length; start += 400) {
    final chunk = ids.sublist(start, (start + 400).clamp(0, ids.length));
    final rows = await db
        .customSelect(
          'SELECT id, content FROM notes WHERE id IN '
          '(${List.filled(chunk.length, '?').join(',')})',
          variables: [for (final id in chunk) Variable.withString(id)],
        )
        .get();
    for (final r in rows) {
      bodies[r.read<String>('id')] = r.read<String>('content');
    }
  }
  final writes = <(String, String, bool, String)>[];
  for (final entry in byId.entries) {
    final content = bodies[entry.key];
    if (content == null) continue; // deleted meanwhile
    final locked = isLockedContent(content);
    final preview = locked ? '' : storedPreviewOf(content);
    items[entry.value] = items[entry.value].withPreview(preview, locked);
    writes.add((entry.key, preview, locked, content));
  }
  await db.batch((b) {
    for (final (id, preview, locked, content) in writes) {
      b.customStatement(
        'INSERT OR REPLACE INTO note_previews (note_id, preview, locked) '
        'SELECT ?, ?, ? WHERE EXISTS '
        '(SELECT 1 FROM notes WHERE id = ? AND content = ?)',
        [id, preview, locked ? 1 : 0, id, content],
      );
    }
  });
}

final notesListProvider = StreamProvider.autoDispose<List<NoteListItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return watchNoteList(db, const AllNotes());
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

final visibleNotesProvider = StreamProvider.autoDispose<List<NoteListItem>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return watchNoteList(db, ref.watch(notesFilterProvider));
});

/// Pins [noteId] to the top of the Notes list, or unpins it.
Future<void> setNotePinned(AppDatabase db, String noteId, bool pinned) =>
    (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(pinned: Value(pinned)),
    );
