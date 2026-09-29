import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../notes/note_content.dart';
import '../notes/note_editor_screen.dart';
import 'highlights.dart';

/// Appends [highlight] (quote, page link, comment) to a note and links the
/// note to the paper. With no [noteId] a new note is created, titled after
/// the paper. Returns the note's id. UI-free, so it can be tested.
Future<String> quoteHighlightIntoNote(
  AppDatabase db, {
  required Highlight highlight,
  required Paper paper,
  String? noteId,
}) async {
  return db.transaction(() async {
    final id = noteId ?? const Uuid().v4();
    if (noteId == null) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value('Notes on ${paper.title}'),
            ),
          );
    }
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        content: Value(
          appendQuote(
            note.content,
            quote: highlight.quote,
            page: highlight.pageNumber,
            pageLink: paperPageLink(paper.id, highlight.pageNumber),
            comment: highlight.comment,
          ),
        ),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await db
        .into(db.notePaperRefs)
        .insert(
          NotePaperRefsCompanion.insert(noteId: id, paperId: paper.id),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  });
}

/// Asks which note the quote goes into — a new one, notes already about
/// this paper, or recent notes — then adds it and opens that note.
Future<void> showQuoteToNoteSheet(
  BuildContext context,
  WidgetRef ref,
  Highlight highlight,
) async {
  final db = ref.read(databaseProvider);
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(highlight.paperId))).getSingle();
  final linked =
      await (db.select(db.notes).join([
            innerJoin(
              db.notePaperRefs,
              db.notePaperRefs.noteId.equalsExp(db.notes.id),
            ),
          ])..where(db.notePaperRefs.paperId.equals(paper.id)))
          .map((r) => r.readTable(db.notes))
          .get();
  final linkedIds = {for (final n in linked) n.id};
  final recent =
      await (db.select(db.notes)
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)])
            ..limit(15))
          .get();
  if (!context.mounted) return;

  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      Widget noteTile(Note n) => ListTile(
        leading: const Icon(Icons.edit_note_outlined),
        title: Text(
          n.title.isEmpty ? 'Untitled' : n.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => Navigator.pop(context, n.id),
      );
      final others = recent.where((n) => !linkedIds.contains(n.id)).toList();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New note'),
                subtitle: Text(
                  'Notes on ${paper.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, ''),
              ),
              if (linked.isNotEmpty) ...[
                const _SheetHeader('About this paper'),
                ...linked.map(noteTile),
              ],
              if (others.isNotEmpty) ...[
                const _SheetHeader('Recent notes'),
                ...others.map(noteTile),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (choice == null) return;

  final noteId = await quoteHighlightIntoNote(
    db,
    highlight: highlight,
    paper: paper,
    noteId: choice.isEmpty ? null : choice,
  );
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: noteId)));
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
