import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/trash.dart';

/// Moves a note to the trash and offers Undo. Used by swiping a note away
/// and by the editor's menu. [messenger] is captured by the caller, since
/// the screen that triggered this may be gone by the time Undo is tapped.
Future<void> deleteNoteWithUndo(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  String noteId,
  String title,
) async {
  final db = ref.read(databaseProvider);
  final trashId = await trashNote(db, noteId);
  _offerUndo(messenger, db, trashId, title.isEmpty ? 'Note' : '“$title”');
}

Future<void> deletePaperWithUndo(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  String paperId,
  String title,
) async {
  final db = ref.read(databaseProvider);
  final trashId = await trashPaper(db, paperId);
  _offerUndo(messenger, db, trashId, '“$title”');
}

void _offerUndo(
  ScaffoldMessengerState messenger,
  AppDatabase db,
  String trashId,
  String label,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$label moved to trash'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => restoreFromTrash(db, trashId),
        ),
      ),
    );
}
