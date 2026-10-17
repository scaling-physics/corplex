import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text typed into a locked note in the instant the notes locked (a timer,
/// the app going to the background, "Close All Locked Notes"), before the
/// autosave could encrypt it — the key is gone by then. Held in memory only,
/// per note, until the note is next opened unlocked, when the editor takes
/// it and saves it (encrypted) like any other edit. Never written anywhere.
class LockedEditRescue {
  final _pending = <String, ({String title, String content})>{};

  void keep(String noteId, String title, String content) =>
      _pending[noteId] = (title: title, content: content);

  /// The kept edit for [noteId], removed.
  ({String title, String content})? take(String noteId) =>
      _pending.remove(noteId);

  bool has(String noteId) => _pending.containsKey(noteId);
}

final lockedEditRescueProvider = Provider<LockedEditRescue>(
  (ref) => LockedEditRescue(),
);
