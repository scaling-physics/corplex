import '../lock/note_lock_service.dart';

/// A note body as plain Delta text for features that read many notes at
/// once (outline, coverage, to-dos, abbreviations, figures, exports).
///
/// Not locked: [content] as is. Locked and its key unlocked: decrypted.
/// Locked and not readable now (or damaged): null — callers show "Locked"
/// or skip the note; they never see the envelope.
Future<String?> readableNoteContent(
  NoteLockService lock,
  String noteId,
  String content,
) async {
  if (!isLockedContent(content)) return content;
  if (!lock.canRead(content)) return null;
  try {
    return await lock.decryptBody(noteId, content);
  } on NoteLockedException {
    return null;
  } on Object {
    return null; // NoteDecryptException: damaged envelope
  }
}

/// The readable text of every locked note in [notes] the reader has
/// unlocked, by note id. Notes that aren't locked, or are locked and
/// unreadable, are absent.
Future<Map<String, String>> unlockedContents(
  NoteLockService? lock,
  Iterable<({String id, String content})> notes,
) async {
  final out = <String, String>{};
  if (lock == null) return out;
  for (final n in notes) {
    if (!isLockedContent(n.content)) continue;
    final text = await readableNoteContent(lock, n.id, n.content);
    if (text != null) out[n.id] = text;
  }
  return out;
}
