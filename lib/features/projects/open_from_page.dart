import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/adaptive.dart';

/// Opens a note from a page pushed over home (a project page, the map).
/// With a detail pane the note belongs in the pane, so the page steps aside
/// first; otherwise it opens as one more page.
void openNoteFromPage(BuildContext context, WidgetRef ref, String noteId) {
  if (hasDetailPane(context)) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  openNote(context, ref, noteId);
}

/// As [openNoteFromPage], for a paper.
void openPaperFromPage(BuildContext context, WidgetRef ref, String paperId) {
  if (hasDetailPane(context)) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  openPaper(context, ref, paperId);
}
