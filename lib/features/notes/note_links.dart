import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// Links between notes are ordinary Quill links, `corplex://note/<id>`, so
/// they survive sync, copy/paste and export like any other link. Their
/// text is the target's title at the time of linking.
String noteLink(String noteId) => 'corplex://note/$noteId';

String? parseNoteLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'corplex' ||
      uri.host != 'note' ||
      uri.pathSegments.length != 1) {
    return null;
  }
  return uri.pathSegments.single;
}

/// Notes that link to [noteId] — found by the link text itself in their
/// content, so there's no separate index to keep in sync.
final backlinksProvider = StreamProvider.autoDispose.family<List<Note>, String>(
  (ref, noteId) {
    final db = ref.watch(databaseProvider);
    return (db.select(db.notes)
          ..where(
            (n) =>
                n.content.like('%${noteLink(noteId)}%') &
                n.id.equals(noteId).not(),
          )
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .watch();
  },
);
