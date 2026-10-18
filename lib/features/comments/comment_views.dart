import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lock/note_lock_service.dart';
import 'comments_data.dart';

/// A note's comments, readable, newest first. A comment that can't be
/// decrypted (the notes are locked again) is left out until they unlock.
final commentViewsProvider = FutureProvider.autoDispose
    .family<List<CommentView>, String>((ref, noteId) async {
      final rows = await ref.watch(noteCommentRowsProvider(noteId).future);
      // Re-read when the notes lock or unlock.
      ref.watch(noteLockServiceProvider);
      final store = ref.read(commentStoreProvider);
      final out = <CommentView>[];
      for (final r in rows) {
        try {
          out.add(await store.view(r));
        } on NoteLockedException {
          // Hidden until unlocked.
        } catch (_) {
          // Damaged envelope: nothing to show.
        }
      }
      return out;
    });
