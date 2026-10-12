import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_riverpod/legacy.dart';

/// A request to open [noteId] with [selection] selected, for an editor that
/// is created (or already open) in the tablet detail pane, where a route
/// argument can't reach it. The editor takes the request and clears it.
/// See `openNoteAtSelection` in `todos.dart`.
typedef NoteSelectionRequest = ({String noteId, TextSelection selection});

final pendingNoteSelectionProvider = StateProvider<NoteSelectionRequest?>(
  (ref) => null,
);
