import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../home/adaptive.dart';
import '../notes/citation_embed.dart' show citationsToEmbeds;
import '../notes/math_markers.dart' show mathToEmbeds;
import '../notes/note_content.dart' show decodeNoteContent;
import '../notes/note_editor_screen.dart';
import 'coverage.dart' show ChapterQuery;
import 'open_from_page.dart';
import 'todos_request.dart';

/// Markers a writer leaves in a note for later.
///
/// * `TODO` (the word, case-sensitive, `TODO:` too): the rest of the line,
///   up to ~120 characters, is the text.
/// * `[@?]`: a claim that needs a citation; the sentence around it is the
///   text. It stays plain text in the editor (not a citation chip: `?` is
///   not a citekey character, so `citationsToEmbeds` leaves it alone).
/// * `[fig: caption]` / `[FIG]`: a figure still to come.
enum TodoKind { todo, needsCitation, figure }

class WritingTodo {
  const WritingTodo({
    required this.kind,
    required this.text,
    required this.offset,
    required this.length,
  });

  final TodoKind kind;

  /// What to show in a list.
  final String text;

  /// Where the marker starts, in the editor's offsets (the document the
  /// editor shows: each citation chip, maths embed or sketch is one
  /// character).
  final int offset;

  /// Length of the marker itself, for selecting it.
  final int length;

  TextSelection get selection =>
      TextSelection(baseOffset: offset, extentOffset: offset + length);

  @override
  String toString() => 'WritingTodo($kind, "$text", $offset+$length)';
}

const _maxText = 120;

String _clip(String s) {
  final t = s.replaceAll('￼', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= _maxText ? t : '${t.substring(0, _maxText).trimRight()}…';
}

final _todoWord = RegExp(
  r'(?<![\p{L}\p{N}_])TODO(?![\p{L}\p{N}_]):?',
  unicode: true,
);
final _needsCite = RegExp(r'\[@\?\]');
final _figure = RegExp(r'\[fig:\s*([^\]\n]*)\]|\[FIG\]');

/// The to-dos in a note's *stored* content, in document order.
///
/// Offsets are measured on the document the editor shows, built the way the
/// editor builds it (maths and citations become embeds, one character
/// each), so selecting `offset` .. `offset + length` in the editor lands on
/// the marker even after chips earlier in the text.
List<WritingTodo> findTodos(String storedContent) {
  final plain = decodeNoteContent(
    citationsToEmbeds(mathToEmbeds(storedContent)),
  ).toPlainText();
  final out = <WritingTodo>[];
  final taken = <(int, int)>[];

  for (final m in _figure.allMatches(plain)) {
    final caption = (m.group(1) ?? '').trim();
    out.add(
      WritingTodo(
        kind: TodoKind.figure,
        text: caption.isEmpty ? 'Figure' : _clip(caption),
        offset: m.start,
        length: m.end - m.start,
      ),
    );
    taken.add((m.start, m.end));
  }

  for (final m in _needsCite.allMatches(plain)) {
    // The sentence around the marker: back to the previous sentence end or
    // line start, forward to the next.
    var start = m.start;
    while (start > 0) {
      final ch = plain[start - 1];
      if (ch == '\n') break;
      if ('.!?'.contains(ch) && start < plain.length && plain[start] == ' ') {
        break;
      }
      start--;
    }
    var end = m.end;
    while (end < plain.length) {
      final ch = plain[end];
      if (ch == '\n') break;
      if ('.!?'.contains(ch) &&
          (end + 1 >= plain.length || ' \n'.contains(plain[end + 1]))) {
        end++;
        break;
      }
      end++;
    }
    final context = _clip(
      plain.substring(start, m.start) + plain.substring(m.end, end),
    );
    out.add(
      WritingTodo(
        kind: TodoKind.needsCitation,
        text: context.isEmpty ? 'Needs a citation' : context,
        offset: m.start,
        length: m.end - m.start,
      ),
    );
    taken.add((m.start, m.end));
  }

  for (final m in _todoWord.allMatches(plain)) {
    if (taken.any((t) => m.start >= t.$1 && m.start < t.$2)) continue;
    var end = plain.indexOf('\n', m.end);
    if (end < 0) end = plain.length;
    final rest = _clip(plain.substring(m.end, end));
    out.add(
      WritingTodo(
        kind: TodoKind.todo,
        text: rest.isEmpty ? 'TODO' : rest,
        offset: m.start,
        length: m.end - m.start,
      ),
    );
  }

  out.sort((a, b) => a.offset.compareTo(b.offset));
  return out;
}

/// One chapter's to-dos.
class ChapterTodos {
  const ChapterTodos({
    required this.noteId,
    required this.title,
    required this.todos,
  });
  final String noteId;
  final String title;
  final List<WritingTodo> todos;
}

/// To-dos across the chapters, in chapter order; chapters without any are
/// left out.
final todosProvider = StreamProvider.autoDispose
    .family<List<ChapterTodos>, ChapterQuery>((ref, query) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.notes,
      )..where((n) => n.id.isIn(query.noteIds))).watch().map((notes) {
        final byId = {for (final n in notes) n.id: n};
        return [
          for (final id in query.noteIds)
            if (byId[id] case final n?)
              if (findTodos(n.content) case final todos when todos.isNotEmpty)
                ChapterTodos(noteId: n.id, title: n.title, todos: todos),
        ];
      });
    });

/// Opens a note from a page with [selection] selected and scrolled into view.
///
/// Below 900 px the note is pushed as a page with
/// [NoteEditorScreen.initialSelection]. With a detail pane (900 px and up)
/// the page steps aside first (like [openNoteFromPage]), and since the pane
/// builds its own editor, the request travels through
/// [pendingNoteSelectionProvider], which a new or already-open editor for
/// that note takes.
void openNoteAtSelection(
  BuildContext context,
  WidgetRef ref,
  String noteId,
  TextSelection selection,
) {
  if (hasDetailPane(context)) {
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r.isFirst);
    ref.read(pendingNoteSelectionProvider.notifier).state = (
      noteId: noteId,
      selection: selection,
    );
    ref.read(selectedNoteProvider.notifier).state = noteId;
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          NoteEditorScreen(noteId: noteId, initialSelection: selection),
    ),
  );
}

/// "To do in the writing (4)": every marker left in the chapters, grouped by
/// chapter in order. Tapping one opens the note with the marker selected.
/// Nothing at all when there are none.
class ProjectTodosSection extends ConsumerWidget {
  const ProjectTodosSection({
    super.key,
    required this.projectId,
    required this.orderedNoteIds,
  });

  final String projectId;
  final List<String> orderedNoteIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref
        .watch(todosProvider(ChapterQuery(projectId, orderedNoteIds)))
        .value;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final count = groups.fold(0, (a, g) => a + g.todos.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Text(
            'To do in the writing ($count)',
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              g.title.trim().isEmpty ? 'Untitled' : g.title.trim(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final t in g.todos)
            ListTile(
              key: ValueKey('todo-${g.noteId}-${t.offset}'),
              dense: true,
              leading: Icon(
                switch (t.kind) {
                  TodoKind.todo => Icons.check_box_outline_blank,
                  TodoKind.needsCitation => Icons.format_quote_outlined,
                  TodoKind.figure => Icons.image_outlined,
                },
                size: 20,
                color: switch (t.kind) {
                  TodoKind.needsCitation => theme.colorScheme.tertiary,
                  _ => theme.colorScheme.onSurfaceVariant,
                },
              ),
              title: Text(t.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () =>
                  openNoteAtSelection(context, ref, g.noteId, t.selection),
            ),
        ],
      ],
    );
  }
}
