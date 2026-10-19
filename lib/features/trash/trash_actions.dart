import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/trash.dart';
import '../../l10n/l10n.dart';

/// Moves a note to the trash and offers Undo. Used by swiping a note away
/// and by the editor's menu. [messenger] is captured by the caller, since
/// the screen that triggered this may be gone by the time Undo is tapped.
/// The messenger sits above the app's localizations, so callers pass their
/// own [l10n] (`context.l10n`); without one the device language is used.
Future<void> deleteNoteWithUndo(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  String noteId,
  String title, {
  AppLocalizations? l10n,
}) async {
  final db = ref.read(databaseProvider);
  final text = l10n ?? deviceL10n();
  final trashId = await trashNote(db, noteId);
  _offerUndo(
    messenger,
    db,
    trashId,
    title.isEmpty ? text.trashKindNote : text.trashQuoted(title),
    text,
  );
}

Future<void> deletePaperWithUndo(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  String paperId,
  String title, {
  AppLocalizations? l10n,
}) async {
  final db = ref.read(databaseProvider);
  final text = l10n ?? deviceL10n();
  final trashId = await trashPaper(db, paperId);
  _offerUndo(messenger, db, trashId, text.trashQuoted(title), text);
}

void _offerUndo(
  ScaffoldMessengerState messenger,
  AppDatabase db,
  String trashId,
  String label,
  AppLocalizations l10n,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.trashMovedToTrash(label)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => restoreFromTrash(db, trashId),
        ),
      ),
    );
}
