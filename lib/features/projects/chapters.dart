import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/projects_table.dart' show ChapterStatus;
import '../notes/note_content.dart';
import '../notes/note_stats.dart';
import '../notes/note_versions.dart';

export '../../data/tables/projects_table.dart' show ChapterStatus;

/// One note in a project's outline.
class Chapter {
  const Chapter({
    required this.note,
    required this.status,
    required this.wordTarget,
    required this.words,
    required this.position,
  });

  final Note note;
  final ChapterStatus? status;
  final int? wordTarget;
  final int words;

  /// Stored position; null until the writer first reorders.
  final int? position;

  String get title =>
      note.title.trim().isEmpty ? 'Untitled' : note.title.trim();

  /// 0..1 progress toward the target, null without one.
  double? get progress => wordTarget == null || wordTarget! <= 0
      ? null
      : (words / wordTarget!).clamp(0.0, 1.0);
}

typedef ProjectNoteRow = ({Note note, ProjectNote link});

/// Chapter order: stored positions first, then notes never placed, oldest
/// first (the order a project had before chapters existed).
int compareChapterRows(ProjectNoteRow a, ProjectNoteRow b) {
  final pa = a.link.position;
  final pb = b.link.position;
  if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
  if (pa != null && pb == null) return -1;
  if (pa == null && pb != null) return 1;
  final c = a.note.createdAt.compareTo(b.note.createdAt);
  return c != 0 ? c : a.note.id.compareTo(b.note.id);
}

Selectable<ProjectNoteRow> _rows(AppDatabase db, String projectId) {
  final query = db.select(db.notes).join([
    innerJoin(db.projectNotes, db.projectNotes.noteId.equalsExp(db.notes.id)),
  ])..where(db.projectNotes.projectId.equals(projectId));
  return query.map(
    (r) => (note: r.readTable(db.notes), link: r.readTable(db.projectNotes)),
  );
}

/// A project's notes in chapter order (used by export and the outline).
Future<List<Note>> orderedProjectNotes(AppDatabase db, String projectId) async {
  final rows = await _rows(db, projectId).get();
  return [for (final r in rows..sort(compareChapterRows)) r.note];
}

/// A project's notes in chapter order.
final projectNotesProvider = StreamProvider.autoDispose
    .family<List<Note>, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      return _rows(db, id).watch().map(
        (rows) => [for (final r in rows..sort(compareChapterRows)) r.note],
      );
    });

/// The outline: ordered chapters with status, target and live word count.
final projectChaptersProvider = StreamProvider.autoDispose
    .family<List<Chapter>, String>((ref, id) {
      final db = ref.watch(databaseProvider);
      return _rows(db, id).watch().map((rows) {
        rows.sort(compareChapterRows);
        return [
          for (final r in rows)
            Chapter(
              note: r.note,
              status: r.link.status,
              wordTarget: r.link.wordTarget,
              words: noteStats(decodeNoteContent(r.note.content)).words,
              position: r.link.position,
            ),
        ];
      });
    });

/// Totals shown in the outline header.
class ChapterSummary {
  ChapterSummary(List<Chapter> chapters)
    : count = chapters.length,
      words = chapters.fold(0, (s, c) => s + c.words),
      target = chapters.fold(0, (s, c) => s + (c.wordTarget ?? 0)),
      finished = chapters
          .where((c) => c.status == ChapterStatus.finished)
          .length,
      anyStatus = chapters.any((c) => c.status != null);

  final int count;
  final int words;
  final int target;
  final int finished;
  final bool anyStatus;

  /// "12,400 / 40,000 words", or "12,400 words" with no targets.
  String get wordsLabel => target > 0
      ? '${formatCount(words)} / ${formatCount(target)} words'
      : '${formatCount(words)} words';

  String get finishedLabel =>
      '$finished of $count chapter${count == 1 ? '' : 's'} final';
}

String formatCount(int n) => NumberFormat.decimalPattern('en').format(n);

String chapterStatusLabel(ChapterStatus s) => switch (s) {
  ChapterStatus.outline => 'Outline',
  ChapterStatus.draft => 'Draft',
  ChapterStatus.withSupervisor => 'With supervisor',
  ChapterStatus.revised => 'Revised',
  ChapterStatus.finished => 'Final',
};

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Due 14 March · 152 days" (the year is added when it isn't this one).
String dueLabel(DateTime due, DateTime now) {
  final d = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final date =
      '${d.day} ${_months[d.month - 1]}${d.year == today.year ? '' : ' ${d.year}'}';
  final rest = days == 0
      ? 'today'
      : days > 0
      ? '$days day${days == 1 ? '' : 's'}'
      : '${-days} day${days == -1 ? '' : 's'} ago';
  return days == 0 ? 'Due today · $date' : 'Due $date · $rest';
}

/// Writes positions 0..n-1 for [orderedNoteIds] (only rows that change).
Future<void> reorderChapters(
  AppDatabase db,
  String projectId,
  List<String> orderedNoteIds,
) => db.transaction(() async {
  final existing = {
    for (final r in await (db.select(
      db.projectNotes,
    )..where((r) => r.projectId.equals(projectId))).get())
      r.noteId: r,
  };
  for (final (i, id) in orderedNoteIds.indexed) {
    final row = existing[id];
    if (row == null || row.position == i) continue;
    await (db.update(db.projectNotes)
          ..where((r) => r.projectId.equals(projectId) & r.noteId.equals(id)))
        .write(ProjectNotesCompanion(position: Value(i)));
  }
});

Future<void> setChapterStatus(
  AppDatabase db,
  String projectId,
  String noteId,
  ChapterStatus? status,
) async {
  final where = db.select(db.projectNotes)
    ..where((r) => r.projectId.equals(projectId) & r.noteId.equals(noteId));
  final before = (await where.getSingleOrNull())?.status;
  await (db.update(db.projectNotes)
        ..where((r) => r.projectId.equals(projectId) & r.noteId.equals(noteId)))
      .write(ProjectNotesCompanion(status: Value(status)));
  // Handing a chapter over keeps a copy of what was sent.
  if (status == ChapterStatus.withSupervisor &&
      before != ChapterStatus.withSupervisor) {
    await saveNoteVersion(
      db,
      noteId,
      label: sentToSupervisorLabel,
      skipIfUnchanged: true,
    );
  }
}

Future<void> setChapterTarget(
  AppDatabase db,
  String projectId,
  String noteId,
  int? words,
) =>
    (db.update(db.projectNotes)..where(
          (r) => r.projectId.equals(projectId) & r.noteId.equals(noteId),
        ))
        .write(
          ProjectNotesCompanion(
            wordTarget: Value(words == null || words <= 0 ? null : words),
          ),
        );

Future<void> setProjectDueDate(
  AppDatabase db,
  String projectId,
  DateTime? due,
) => (db.update(db.projects)..where((p) => p.id.equals(projectId))).write(
  ProjectsCompanion(
    dueDate: Value(due == null ? null : DateTime(due.year, due.month, due.day)),
  ),
);

/// Makes a new note and puts it last in the outline; returns its id.
Future<String> addChapter(AppDatabase db, String projectId) async {
  final id = const Uuid().v4();
  await db.transaction(() async {
    // Place every note first, so the new one really lands at the end.
    final current = await orderedProjectNotes(db, projectId);
    await db.into(db.notes).insert(NotesCompanion.insert(id: Value(id)));
    await reorderChapters(db, projectId, [for (final n in current) n.id]);
    await db
        .into(db.projectNotes)
        .insert(
          ProjectNotesCompanion.insert(
            projectId: projectId,
            noteId: id,
            position: Value(current.length),
          ),
        );
  });
  return id;
}
