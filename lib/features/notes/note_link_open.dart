import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../home/adaptive.dart';
import '../lock/note_lock_service.dart';
import '../projects/readable_content.dart';
import '../projects/todos.dart' show openNoteAtSelection;
import 'note_links.dart';
import 'note_sections.dart';

/// Opens the note a link names. A link to a heading or paragraph opens the
/// note with that part selected (revealing folds, in the detail pane too);
/// when the part isn't there any more, or the note can't be read (locked),
/// the note opens at the top.
Future<void> openNoteLink(
  BuildContext context,
  WidgetRef ref,
  NoteLinkTarget target,
) async {
  if (target.heading == null && target.block == null) {
    openNote(context, ref, target.noteId);
    return;
  }
  final db = ref.read(databaseProvider);
  final lock = ref.read(noteLockServiceProvider);
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(target.noteId))).getSingleOrNull();
  final body = note == null
      ? null
      : await readableNoteContent(lock, note.id, note.content);
  final selection = body == null ? null : selectionInContent(body, target);
  if (!context.mounted) return;
  if (selection == null) {
    openNote(context, ref, target.noteId);
  } else {
    openNoteAtSelection(context, ref, target.noteId, selection);
  }
}
