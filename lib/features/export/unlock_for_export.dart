import 'package:flutter/material.dart';

import '../lock/note_lock_service.dart';
import '../lock/notes_password_dialogs.dart' show requestNotesUnlock;

/// Asks the reader to unlock their locked notes (Face ID / Touch ID /
/// fingerprint when set up, else the notes password with its hint). True
/// once they're unlocked. The same dialog as everywhere else
/// (`requestNotesUnlock`); [reason] says what for.
Future<bool> requestUnlock(
  BuildContext context,
  NoteLockService lock, {
  String reason = 'Unlock your locked notes to continue.',
}) => requestNotesUnlock(context, lock, reason: reason);

/// [content] of note [noteId] as plain Delta JSON for something that must
/// read the body: as is when not locked, decrypted when its key is
/// unlocked, otherwise after asking to unlock. Null if the reader declined
/// or the body is damaged.
Future<String?> readableForAction(
  BuildContext context,
  NoteLockService lock,
  String noteId,
  String content, {
  String reason = 'Unlock this note to continue.',
}) async {
  if (!isLockedContent(content)) return content;
  if (!lock.canRead(content)) {
    if (!await requestUnlock(context, lock, reason: reason)) return null;
    if (!lock.canRead(content)) return null;
  }
  try {
    return await lock.decryptBody(noteId, content);
  } on Object {
    return null;
  }
}
