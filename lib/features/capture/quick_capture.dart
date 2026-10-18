/// Something captured from outside Corplex's window on macOS: the global
/// Quick Note hotkey, the Dock menu's New Note, or the Services menu's
/// "New Corplex Note" with the selected text.
sealed class QuickCapture {
  const QuickCapture();
}

/// Make a new note and put the cursor in its body.
class NewNoteCapture extends QuickCapture {
  const NewNoteCapture();
}

/// Text from another app (Services). Handled like a share: a DOI or arXiv
/// id becomes a paper, a link a link note, anything else a note.
class TextCapture extends QuickCapture {
  const TextCapture(this.text);

  final String text;
}

/// Decodes the `capture` channel message: the string `newNote` or
/// `{text: ...}`. Null for anything else.
QuickCapture? quickCaptureFromMessage(Object? message) {
  if (message == 'newNote') return const NewNoteCapture();
  if (message is Map && message['text'] is String) {
    return TextCapture(message['text'] as String);
  }
  return null;
}
