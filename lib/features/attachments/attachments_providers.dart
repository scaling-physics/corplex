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
      // Selected by column, not whole rows: a note's body (megabytes across
      // the library) is only needed to see whether it is locked, and that is
      // in the first bytes. A paper's row isn't needed at all.
      final head = db.notes.content.substr(1, 120);
      final query =
          db.select(db.attachments).join([
              leftOuterJoin(
                db.notes,
                db.notes.id.equalsExp(db.attachments.noteId),
                useColumns: false,
              ),
              leftOuterJoin(
                db.papers,
                db.papers.id.equalsExp(db.attachments.paperId),
                useColumns: false,
              ),
            ])
            ..addColumns([
              db.notes.id,
              db.notes.title,
              head,
              db.papers.id,
              db.papers.title,
            ])
            ..orderBy([
              OrderingTerm.desc(db.attachments.createdAt),
              OrderingTerm.asc(db.attachments.id),
            ]);
      return query.watch().map((rows) {
        final out = <AttachmentEntry>[];
        for (final row in rows) {
          final a = row.readTable(db.attachments);
          final noteId = row.read(db.notes.id);
          final paperId = row.read(db.papers.id);
          if (noteId != null && !lock.canRead(row.read(head) ?? '')) continue;
          if (noteId == null && paperId == null) continue;
          final noteTitle = row.read(db.notes.title)?.trim() ?? '';
          final paperTitle = row.read(db.papers.title)?.trim() ?? '';
          out.add(
            AttachmentEntry(
              attachment: a,
              noteId: noteId,
              paperId: noteId == null ? paperId : null,
              parentTitle: noteId != null
                  ? (noteTitle.isEmpty ? 'Untitled' : noteTitle)
                  : (paperTitle.isEmpty ? 'Untitled paper' : paperTitle),
            ),
          );
        }
        return out;
      });
    });
