import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../notes/editor_document.dart';
import '../notes/figure_markers.dart';
import '../notes/note_content.dart';
import 'chapters.dart';

export '../notes/figure_markers.dart' show FigureKind;

/// One numbered figure or table.
class FigureEntry {
  const FigureEntry({
    required this.kind,
    required this.label,
    required this.caption,
    required this.number,
    required this.noteId,
    required this.noteTitle,
  });

  final FigureKind kind;
  final String label;

  /// The caption as written (references and citations as marker text).
  final String caption;

  /// "3.2" in a project chapter, "2" for a note outside any project.
  final String number;
  final String noteId;
  final String noteTitle;

  /// "Figure 3.2".
  String get name => '${kind.title} $number';

  @override
  bool operator ==(Object other) =>
      other is FigureEntry &&
      other.kind == kind &&
      other.label == label &&
      other.caption == caption &&
      other.number == number &&
      other.noteId == noteId &&
      other.noteTitle == noteTitle;

  @override
  int get hashCode =>
      Object.hash(kind, label, caption, number, noteId, noteTitle);
}

/// A note to number: [chapter] is its 1-based position in its project
/// ("3"), or null for a note in no project.
class FigureNote {
  const FigureNote({
    required this.noteId,
    required this.title,
    required this.content,
    this.chapter,
  });

  final String noteId;
  final String title;
  final String content;
  final String? chapter;
}

/// Every figure and table across some notes, numbered.
class FigureIndex {
  FigureIndex(this.entries) {
    for (final e in entries) {
      _byKey.putIfAbsent('${e.kind.tag}:${e.label}', () => e);
    }
  }

  static final empty = FigureIndex(const []);

  /// In note order, then document order.
  final List<FigureEntry> entries;
  final _byKey = <String, FigureEntry>{};

  /// The first definition of [label] (a label defined twice keeps the first).
  FigureEntry? find(FigureKind kind, String label) =>
      _byKey['${kind.tag}:$label'];

  /// "Figure 3.2", or "Figure ??" for a label nothing defines.
  String nameOf(FigureKind kind, String label) =>
      find(kind, label)?.name ?? '${kind.title} ??';

  Iterable<FigureEntry> ofKind(FigureKind kind) =>
      entries.where((e) => e.kind == kind);

  bool get isEmpty => entries.isEmpty;

  /// [text] with its `{@fig:x}` references written out.
  String resolve(String text) => replaceFigureRefs(text, nameOf);
}

/// Numbers the figures and tables of [notes], in the order given: a
/// figure's number is `chapter.n`, n counting same-kind definitions in its
/// note (tables apart from figures).
FigureIndex buildFigureIndex(List<FigureNote> notes) {
  final out = <FigureEntry>[];
  for (final note in notes) {
    if (!note.content.contains('{#')) continue;
    final defs = figureDefsIn(
      decodeNoteContent(figuresToEmbeds(note.content)).toDelta(),
    );
    final counts = <FigureKind, int>{};
    for (final d in defs) {
      final n = counts[d.kind] = (counts[d.kind] ?? 0) + 1;
      out.add(
        FigureEntry(
          kind: d.kind,
          label: d.label,
          caption: d.caption,
          number: note.chapter == null ? '$n' : '${note.chapter}.$n',
          noteId: note.noteId,
          noteTitle: note.title,
        ),
      );
    }
  }
  return FigureIndex(out);
}

/// What a note needs to number its chips: its chapter and the project's
/// figures. A note in several projects uses the **first project by
/// creation date**; a note in none is numbered "n".
class FigureContext {
  const FigureContext(this.chapter, this.index);

  /// "3", or null outside a project.
  final String? chapter;
  final FigureIndex index;

  static final none = FigureContext(null, FigureIndex.empty);
}

/// Numbering for [orderedNotes] (a project's chapters, in order).
FigureIndex projectFigureIndex(
  List<Note> orderedNotes, {
  String? replaceId,
  String? replaceContent,
}) => buildFigureIndex([
  for (final (i, n) in orderedNotes.indexed)
    FigureNote(
      noteId: n.id,
      title: n.title,
      content: n.id == replaceId && replaceContent != null
          ? replaceContent
          : n.content,
      chapter: '${i + 1}',
    ),
]);

JoinedSelectStatement<HasResultSet, dynamic> _firstProject(
  AppDatabase db,
  String noteId,
) =>
    db.select(db.projects).join([
        innerJoin(
          db.projectNotes,
          db.projectNotes.projectId.equalsExp(db.projects.id),
        ),
      ])
      ..where(db.projectNotes.noteId.equals(noteId))
      ..orderBy([
        OrderingTerm.asc(db.projects.createdAt),
        OrderingTerm.asc(db.projects.id),
      ])
      ..limit(1);

final _firstProjectIdProvider = StreamProvider.autoDispose
    .family<String?, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      return _firstProject(db, noteId).watch().map(
        (rows) => rows.isEmpty ? null : rows.first.readTable(db.projects).id,
      );
    });

/// The figure numbering for a note, live: follows chapter order, edits in
/// the other chapters and the project the note belongs to.
final figureContextProvider = Provider.autoDispose
    .family<FigureContext, String>((ref, noteId) {
      final projectId = ref.watch(_firstProjectIdProvider(noteId)).value;
      if (projectId == null) return FigureContext.none;
      final notes = ref.watch(projectNotesProvider(projectId)).value;
      if (notes == null) return FigureContext.none;
      final at = notes.indexWhere((n) => n.id == noteId);
      return FigureContext(
        at < 0 ? null : '${at + 1}',
        projectFigureIndex(notes),
      );
    });

/// The numbering for exporting [noteId] on its own: the same numbers the
/// editor shows. [liveContent] is the note's current text (the database
/// may be a moment behind the editor).
Future<FigureIndex> figureIndexForNote(
  AppDatabase db,
  String noteId, {
  String? liveContent,
}) async {
  final first = await _firstProject(db, noteId).get();
  if (first.isNotEmpty) {
    final project = first.first.readTable(db.projects);
    final notes = await orderedProjectNotes(db, project.id);
    if (notes.any((n) => n.id == noteId)) {
      return projectFigureIndex(
        notes,
        replaceId: noteId,
        replaceContent: liveContent,
      );
    }
  }
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  return buildFigureIndex([
    FigureNote(
      noteId: noteId,
      title: note?.title ?? '',
      content: liveContent ?? note?.content ?? '',
    ),
  ]);
}

/// The editor offset of a definition in stored [content], or null.
int? figureOffset(String content, FigureKind kind, String label) {
  if (!content.contains('{#')) return null;
  for (final d in figureDefsIn(editorDocument(content).toDelta())) {
    if (d.kind == kind && d.label == label) return d.offset;
  }
  return null;
}
