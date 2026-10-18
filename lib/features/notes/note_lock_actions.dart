import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/context_menu.dart';
import '../../data/database.dart';
import '../lock/note_lock_service.dart';
import '../lock/notes_password_dialogs.dart';
import '../../data/database_provider.dart';
import 'notes_providers.dart';

/// Saves for the notes open in an editor right now, by note id. An editor
/// registers while it is open, so something that changes the note behind
/// its back (locking it from the list) can flush its typing first.
final openNoteFlushProvider = Provider<Map<String, Future<void> Function()>>(
  (ref) => {},
);

/// Locks [note] from the Notes list (right-click). An open editor learns of
/// it through the database, like any other change.
Future<void> lockNoteFromList(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final service = ref.read(noteLockServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (!await ensureNotesUnlocked(context, service)) return;
  // The editor showing this note saves what's typed first.
  await ref.read(openNoteFlushProvider)[note.id]?.call();
  await service.lockNote(note.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Note locked')));
}

/// Takes the lock off [note] (asking for the password if it isn't unlocked).
Future<void> removeLockFromList(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final service = ref.read(noteLockServiceProvider);
  if (!service.canRead(note.content)) {
    final ok = await showUnlockNotesDialog(context, service);
    if (!ok || !service.canRead(note.content)) return;
  }
  await service.removeLock(note.id);
}

/// The right-click item for [note]: Lock note, or Remove lock.
ContextMenuAction lockMenuAction(
  BuildContext context,
  WidgetRef ref,
  Note note,
) => isLockedContent(note.content)
    ? ContextMenuAction(
        label: 'Remove lock',
        icon: Icons.lock_open_outlined,
        onSelected: () => removeLockFromList(context, ref, note),
      )
    : ContextMenuAction(
        label: 'Lock note',
        icon: Icons.lock_outline,
        onSelected: () => lockNoteFromList(context, ref, note),
      );

/// The right-click item for [note]: Pin to top, or Unpin.
ContextMenuAction pinMenuAction(WidgetRef ref, Note note) => ContextMenuAction(
  label: note.pinned ? 'Unpin' : 'Pin to top',
  icon: note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
  onSelected: () =>
      setNotePinned(ref.read(databaseProvider), note.id, !note.pinned),
);
