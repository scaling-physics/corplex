import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/local_files.dart';
import '../../theme/context_menu.dart';
import '../export/export_actions.dart' show buildStyledExportDoc;
import '../export/export_model.dart' show ExportNote;
import '../export/pdf_export.dart';
import '../export/unlock_for_export.dart' show readableForAction;
import '../home/adaptive.dart' show openNote;
import '../library/citation_formatter.dart' show CitationStyle;
import '../lock/note_lock_service.dart';
import '../platform/mac_window.dart' show macWindowProvider;
import '../projects/figures.dart' show figureIndexForNote;
import 'note_lock_actions.dart' show openNoteFlushProvider;

/// Copies note [noteId] — title, body, folder, tags, linked papers and
/// attachments (files copied too) — and returns the copy's id. Like Apple
/// Notes, the copy keeps the title and isn't pinned or in any project (a
/// copy shouldn't become another chapter). Audio timestamp links in the
/// body point at the copy's own attachments. A locked body is re-encrypted
/// for the copy (its note id is part of the encryption), so the notes must
/// be unlocked: otherwise [NoteLockedException].
Future<String> duplicateNote(
  AppDatabase db,
  NoteLockService lock,
  String noteId,
) async {
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingle();
  final locked = isLockedContent(note.content);
  var body = locked
      ? await lock.decryptBody(noteId, note.content)
      : note.content;
  final id = const Uuid().v4();

  final attachments = await (db.select(
    db.attachments,
  )..where((a) => a.noteId.equals(noteId))).get();
  final copies = <AttachmentsCompanion>[];
  for (final a in attachments) {
    final newId = const Uuid().v4();
    String? path;
    String? storageKey;
    if (a.path != null) {
      try {
        path = await copyIntoAppStorage(a.path!, 'attachments');
      } on Object {
        path = null;
      }
    }
    if (path == null) {
      // The file isn't on this device (not downloaded yet): point at the
      // same stored object. Orphan cleanup keeps it while any row names it.
      storageKey = a.storageKey;
    }
    copies.add(
      AttachmentsCompanion.insert(
        id: Value(newId),
        noteId: Value(id),
        type: a.type,
        title: Value(a.title),
        path: Value(path),
        url: Value(a.url),
        storageKey: Value(storageKey),
      ),
    );
    body = body.replaceAll(a.id, newId);
  }
  final content = locked ? await lock.encryptBody(id, body) : body;

  final tags = await (db.select(
    db.noteTags,
  )..where((t) => t.noteId.equals(noteId))).get();
  final papers = await (db.select(
    db.notePaperRefs,
  )..where((r) => r.noteId.equals(noteId))).get();
  await db.transaction(() async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(note.title),
            content: Value(content),
            folderId: Value(note.folderId),
          ),
        );
    for (final t in tags) {
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: id, tagId: t.tagId));
    }
    for (final r in papers) {
      await db
          .into(db.notePaperRefs)
          .insert(
            NotePaperRefsCompanion.insert(noteId: id, paperId: r.paperId),
          );
    }
    for (final a in copies) {
      await db.into(db.attachments).insert(a);
    }
  });
  return id;
}

/// File → Duplicate Note (⌘D), ⋮ / right-click → Duplicate: copies the note
/// (asking to unlock a locked one) and opens the copy.
Future<void> duplicateNoteAndOpen(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final db = ref.read(databaseProvider);
  final lock = ref.read(noteLockServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(openNoteFlushProvider)[noteId]?.call();
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null || !context.mounted) return;
  final readable = await readableForAction(
    context,
    lock,
    noteId,
    note.content,
    reason: 'Unlock this note to duplicate it.',
  );
  if (readable == null || !context.mounted) return;
  try {
    final id = await duplicateNote(db, lock, noteId);
    if (context.mounted) openNote(context, ref, id);
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('Couldn\'t duplicate that note.')),
    );
  }
}

/// File → Print… (⌘P) on a Mac: the note as the PDF export renders it
/// (citations in APA, figures numbered), through the system print panel.
Future<void> printNote(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final db = ref.read(databaseProvider);
  final lock = ref.read(noteLockServiceProvider);
  final window = ref.read(macWindowProvider);
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(openNoteFlushProvider)[noteId]?.call();
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null || !context.mounted) return;
  final content = await readableForAction(
    context,
    lock,
    noteId,
    note.content,
    reason: 'Unlock this note to print it.',
  );
  if (content == null) return;
  try {
    final figures = await figureIndexForNote(
      db,
      noteId,
      liveContent: content,
      lock: lock,
    );
    final doc = await buildStyledExportDoc(
      db,
      [ExportNote(note.title, content)],
      title: note.title,
      style: CitationStyle.apa,
      figures: figures,
    );
    final pdf = await exportToPdf(doc);
    final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    if (await window.printPdf(pdf, title)) return;
  } on Object {
    // Reported below.
  }
  messenger.showSnackBar(
    const SnackBar(content: Text('Couldn\'t print that note.')),
  );
}

/// The right-click item for [note]: Duplicate.
ContextMenuAction duplicateMenuAction(
  BuildContext context,
  WidgetRef ref,
  Note note,
) => ContextMenuAction(
  label: 'Duplicate',
  icon: Icons.copy_outlined,
  onSelected: () => duplicateNoteAndOpen(context, ref, note.id),
);
