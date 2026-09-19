import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

final attachmentsForNoteProvider = StreamProvider.autoDispose
    .family<List<Attachment>, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.attachments,
      )..where((a) => a.noteId.equals(noteId))).watch();
    });
