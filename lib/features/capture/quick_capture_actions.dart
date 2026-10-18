import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../notes/note_editor_screen.dart' show noteBodyFocusRequestProvider;
import '../notes/notes_screen.dart' show createNote;
import '../share/share_import.dart' show handleSharedItems;
import '../share/shared_items.dart' show classifyShared;
import 'quick_capture.dart';

/// Carries out [capture]. The caller has already returned to the home
/// screen and the Notes tab.
Future<void> handleQuickCapture(
  BuildContext context,
  WidgetRef ref,
  QuickCapture capture,
) async {
  switch (capture) {
    case NewNoteCapture():
      await createNote(context, ref);
      // The pane's editor takes the cursor; a pushed editor focuses itself.
      ref.read(noteBodyFocusRequestProvider.notifier).state++;
    case TextCapture(:final text):
      final items = classifyShared([
        SharedMediaFile(path: text, type: SharedMediaType.text),
      ]);
      if (items.isEmpty || !context.mounted) return;
      await handleSharedItems(context, ref, items);
  }
}
