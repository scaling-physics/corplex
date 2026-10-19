import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/l10n.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/projects_table.dart' show ChapterStatus;
import '../lock/note_lock_service.dart';
import '../notes/note_content.dart';
import '../notes/note_stats.dart';
import '../notes/note_versions.dart';
import 'readable_content.dart';

export '../../data/tables/projects_table.dart' show ChapterStatus;

/// One note in a project's outline.
class Chapter {
  const Chapter({
    required this.note,
    required this.status,
    required this.wordTarget,
    required this.words,
    required this.position,
    this.locked = false,
  });

  final Note note;

  /// A locked chapter whose key isn't unlocked: [words] is 0 and unknown.
  final bool locked;
  final ChapterStatus? status;
  final int? wordTarget;
  final int words;

  /// Stored position; null until the writer first reorders.
  final int? position;

  String get title => titleIn(_english);

  String titleIn(AppLocalizations l10n) =>
      note.title.trim().isEmpty ? l10n.commonUntitled : note.title.trim();

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
      // Watching the service re-counts when notes lock or unlock.
      final lock = ref.watch(noteLockServiceProvider);
      return _rows(db, id).watch().asyncMap((rows) async {
        rows.sort(compareChapterRows);
        final chapters = <Chapter>[];
        for (final r in rows) {
          final content = await readableNoteContent(
            lock,
            r.note.id,
            r.note.content,
          );
          chapters.add(
            Chapter(
              note: r.note,
              status: r.link.status,
              wordTarget: r.link.wordTarget,
              words: content == null
                  ? 0
                  : noteStats(decodeNoteContent(content)).words,
              position: r.link.position,
              locked: content == null,
            ),
          );
        }
        return chapters;
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

  /// "12,400 / 40,000 words", or "12,400 words" with no targets (English
  /// unless [wordsText] is asked for another language).
  String get wordsLabel => wordsText(_english);

  String wordsText(AppLocalizations l10n) => target > 0
      ? l10n.projectsWordsOfTarget(words, target)
      : l10n.projectsWords(words);

  String get finishedLabel => finishedText(_english);

  String finishedText(AppLocalizations l10n) =>
      l10n.projectsChaptersFinal(finished, count);
}

final _english = lookupAppLocalizations(const Locale('en'));

/// [n] with the locale's digit grouping ("12,400" / "12.400").
String formatCount(int n, [String locale = 'en']) =>
    NumberFormat.decimalPattern(locale).format(n);

String chapterStatusLabel(ChapterStatus s, [AppLocalizations? l10n]) {
  final l = l10n ?? _english;
  return switch (s) {
    ChapterStatus.outline => l.projectsStatusOutline,
    ChapterStatus.draft => l.projectsStatusDraft,
    ChapterStatus.withSupervisor => l.projectsStatusWithSupervisor,
    ChapterStatus.revised => l.projectsStatusRevised,
    ChapterStatus.finished => l.projectsStatusFinal,
  };
}

/// "Due 14 March · 152 days" (the year is added when it isn't this one).
String dueLabel(DateTime due, DateTime now, [AppLocalizations? l10n]) {
  final l = l10n ?? _english;
  final d = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final date = DateFormat(
    d.year == today.year ? l.projectsDatePattern : l.projectsDatePatternYear,
    // `en` has no date data until a localization delegate loads it; the
    // built-in `en_US` reads the same for these patterns.
    l.localeName == 'en' ? 'en_US' : l.localeName,
  ).format(d);
  if (days == 0) return l.projectsDueToday(date);
  return l.projectsDue(
    date,
    days > 0 ? l.projectsInDays(days) : l.projectsDaysAgo(-days),
  );
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
  ChapterStatus? status, {
  AppLocalizations? l10n,
}) async {
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
      label: l10n?.notesSentToSupervisor ?? sentToSupervisorLabel,
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
