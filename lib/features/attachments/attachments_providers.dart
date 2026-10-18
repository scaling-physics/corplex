import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/attachment_label.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../data/tables/attachments_table.dart';
import '../audio/audio_link.dart';
import '../lock/note_lock_service.dart';

/// How the browser groups attachments.
enum AttachmentKind {
  image('Images'),
  audio('Audio'),
  link('Links'),
  file('Files');

  const AttachmentKind(this.label);
  final String label;
}

/// An attachment with the note or paper it belongs to.
class AttachmentEntry {
  const AttachmentEntry({
    required this.attachment,
    this.noteId,
    this.paperId,
    required this.parentTitle,
  });

  final Attachment attachment;
  final String? noteId;
  final String? paperId;
  final String parentTitle;

  String get label => attachment.label;

  AttachmentKind get kind {
    final a = attachment;
    if (a.type == AttachmentType.image) return AttachmentKind.image;
    if (isAudioAttachment(a)) return AttachmentKind.audio;
    if ((a.path == null || a.path!.isEmpty) && a.url != null) {
      return AttachmentKind.link;
    }
    return AttachmentKind.file;
  }
}

/// Every attachment, newest first, live. Attachments of locked notes are
/// left out while their key isn't unlocked (the files aren't encrypted, but
/// an image must not show while its note is locked).
final allAttachmentsProvider =
    StreamProvider.autoDispose<List<AttachmentEntry>>((ref) {
      final db = ref.watch(databaseProvider);
      final lock = ref.watch(noteLockServiceProvider);
      final query =
          db.select(db.attachments).join([
            leftOuterJoin(
              db.notes,
              db.notes.id.equalsExp(db.attachments.noteId),
            ),
            leftOuterJoin(
              db.papers,
              db.papers.id.equalsExp(db.attachments.paperId),
            ),
          ])..orderBy([
            OrderingTerm.desc(db.attachments.createdAt),
            OrderingTerm.asc(db.attachments.id),
          ]);
      return query.watch().map((rows) {
        final out = <AttachmentEntry>[];
        for (final row in rows) {
          final a = row.readTable(db.attachments);
          final note = row.readTableOrNull(db.notes);
          final paper = row.readTableOrNull(db.papers);
          if (note != null && !lock.canRead(note.content)) continue;
          if (note == null && paper == null) continue;
          final noteTitle = note?.title.trim() ?? '';
          out.add(
            AttachmentEntry(
              attachment: a,
              noteId: note?.id,
              paperId: note == null ? paper?.id : null,
              parentTitle: note != null
                  ? (noteTitle.isEmpty ? 'Untitled' : noteTitle)
                  : (paper!.title.trim().isEmpty
                        ? 'Untitled paper'
                        : paper.title.trim()),
            ),
          );
        }
        return out;
      });
    });
