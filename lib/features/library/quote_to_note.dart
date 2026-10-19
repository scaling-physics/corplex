import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../export/unlock_for_export.dart' show requestUnlock;
import '../lock/note_lock_service.dart';
import '../notes/note_content.dart';
import '../notes/note_editor_screen.dart';
import 'flight.dart';
import 'highlights.dart';

/// Appends [highlight] (quote, page link, comment) to a note and links the
/// note to the paper. With no [noteId] a new note is created, titled after
/// the paper. Returns the note's id. UI-free, so it can be tested.
///
/// A locked target note is decrypted, appended to and encrypted again, so
/// it stays locked; that needs [lock] with its key unlocked, else this
/// throws [NoteLockedException] and writes nothing (never plain JSON onto
/// an envelope).
Future<String> quoteHighlightIntoNote(
  AppDatabase db, {
  required Highlight highlight,
  required Paper paper,
  String? noteId,
  NoteLockService? lock,
  String? newNoteTitle,
}) async {
  return db.transaction(() async {
    final id = noteId ?? const Uuid().v4();
    if (noteId == null) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(newNoteTitle ?? 'Notes on ${paper.title}'),
            ),
          );
    }
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();
    final locked = isLockedContent(note.content);
    if (locked && lock == null) throw const NoteLockedException();
    final current = locked
        ? await lock!.decryptBody(id, note.content)
        : note.content;
    final appended = appendQuote(
      current,
      quote: highlight.quote,
      page: highlight.pageNumber,
      pageLink: paperPageLink(paper.id, highlight.pageNumber),
      comment: highlight.comment,
    );
    await (db.update(db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        content: Value(
          locked ? await lock!.encryptBody(id, appended) : appended,
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

/// In split view, the note editor beside the reader; quotes go straight
/// into it instead of asking which note. Set by the split reader.
final pairedNoteProvider = StateProvider<NoteEditorHandle?>((ref) => null);

/// Asks which note the quote goes into — a new one, notes already about
/// this paper, or recent notes — then adds it and opens that note. [from]
/// is the selection's rect on screen (global), where the split-view quote
/// flight starts.
Future<void> showQuoteToNoteSheet(
  BuildContext context,
  WidgetRef ref,
  Highlight highlight, {
  Rect? from,
}) async {
  final db = ref.read(databaseProvider);
  final paper = await (db.select(
    db.papers,
  )..where((p) => p.id.equals(highlight.paperId))).getSingle();
  if (ref.read(pairedNoteProvider)?.appendQuote case final append?) {
    await append(
      paperId: paper.id,
      quote: highlight.quote,
      page: highlight.pageNumber,
      pageLink: paperPageLink(paper.id, highlight.pageNumber),
      comment: highlight.comment,
    );
    if (context.mounted) {
      // The quote lifts off the selection and lands in the note pane.
      final landing = paneLanding(ref.read(pairedPaneKeyProvider));
      if (from != null && landing != null) {
        flyAcross(
          context,
          from: from.center,
          to: landing,
          size: QuoteCard.size,
          child: QuoteCard(quote: highlight.quote),
        );
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.viewerQuoteAdded),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    return;
  }
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

  final newTitle = context.l10n.viewerNotesOn(paper.title);
  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      Widget noteTile(Note n) => ListTile(
        leading: const Icon(Icons.edit_note_outlined),
        title: Text(
          n.title.isEmpty ? context.l10n.commonUntitled : n.title,
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
                title: Text(context.l10n.viewerQuoteNewNote),
                subtitle: Text(
                  newTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, ''),
              ),
              if (linked.isNotEmpty) ...[
                _SheetHeader(context.l10n.viewerAboutThisPaper),
                ...linked.map(noteTile),
              ],
              if (others.isNotEmpty) ...[
                _SheetHeader(context.l10n.viewerRecentNotes),
                ...others.map(noteTile),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (choice == null) return;

  final lock = ref.read(noteLockServiceProvider);
  String noteId;
  try {
    noteId = await quoteHighlightIntoNote(
      db,
      highlight: highlight,
      paper: paper,
      noteId: choice.isEmpty ? null : choice,
      lock: lock,
      newNoteTitle: newTitle,
    );
  } on NoteLockedException {
    // The chosen note is locked: unlock to add to it, else leave it alone.
    final ok =
        context.mounted &&
        await requestUnlock(
          context,
          lock,
          reason: context.l10n.viewerUnlockToQuote,
        );
    if (!ok || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.viewerUnlockToAdd)));
      }
      return;
    }
    noteId = await quoteHighlightIntoNote(
      db,
      highlight: highlight,
      paper: paper,
      noteId: choice,
      lock: lock,
    );
  }
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
