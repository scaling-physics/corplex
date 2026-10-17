import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_lock_service.dart';
import 'editor_document.dart';
import 'note_content.dart';
import 'note_stats.dart';

/// Label of the version saved when a chapter goes to the supervisor. The
/// date is shown beside every version, so it isn't repeated here.
const sentToSupervisorLabel = 'Sent to supervisor';

/// Label of the safety copy taken just before a version is restored.
const beforeRestoringLabel = 'Before restoring';

/// Saves a copy of the note as it is *stored* right now (title and body).
/// Callers with an open editor flush its pending typing first. With
/// [skipIfUnchanged], nothing is saved when the newest version already
/// holds this exact title and body (used by the automatic save, so
/// flipping a status back and forth doesn't pile up copies).
Future<void> saveNoteVersion(
  AppDatabase db,
  String noteId, {
  String? label,
  bool skipIfUnchanged = false,
}) async {
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null) return;
  if (skipIfUnchanged) {
    final newest =
        await (db.select(db.noteVersions)
              ..where((v) => v.noteId.equals(noteId))
              ..orderBy([
                (v) => OrderingTerm.desc(v.createdAt),
                (v) => OrderingTerm.desc(v.updatedAt),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (newest != null && sameBody(newest.title, newest.content, note)) return;
  }
  final trimmed = label?.trim();
  await db
      .into(db.noteVersions)
      .insert(
        NoteVersionsCompanion.insert(
          id: Value(const Uuid().v4()),
          noteId: noteId,
          title: Value(note.title),
          content: Value(note.content),
          label: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
          createdAt: Value(DateTime.now()),
        ),
      );
}

/// Whether a version's title and body equal the note's, comparing bodies
/// in normalised Delta form (an empty or plain-text body is the same note
/// as its Delta).
///
/// Locked bodies are compared as stored (each lock uses a fresh nonce, so
/// equal envelopes are the very same copy); use [sameReadableBody] when the
/// plain text of both is at hand.
bool sameBody(String title, String content, Note note) =>
    title == note.title && _sameContent(content, note.content);

bool _sameContent(String a, String b) {
  if (isLockedContent(a) || isLockedContent(b)) return a == b;
  return encodeNoteContent(decodeNoteContent(a)) ==
      encodeNoteContent(decodeNoteContent(b));
}

/// Renames a version. The label is the only thing about a version that
/// can change; empty clears it.
Future<void> setVersionLabel(AppDatabase db, String versionId, String? label) {
  final trimmed = label?.trim();
  return (db.update(
    db.noteVersions,
  )..where((v) => v.id.equals(versionId))).write(
    NoteVersionsCompanion(
      label: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
    ),
  );
}

/// Deletes a version; returns the row so the caller can offer Undo.
Future<NoteVersion?> deleteNoteVersion(AppDatabase db, String versionId) async {
  final row = await (db.select(
    db.noteVersions,
  )..where((v) => v.id.equals(versionId))).getSingleOrNull();
  if (row == null) return null;
  await (db.delete(db.noteVersions)..where((v) => v.id.equals(versionId))).go();
  return row;
}

/// Puts back a version removed by [deleteNoteVersion], stamped "now" so
/// the undo wins over the delete when synced. Does nothing if the note
/// has gone meanwhile.
Future<void> undoDeleteNoteVersion(AppDatabase db, NoteVersion row) async {
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(row.noteId))).getSingleOrNull();
  if (note == null) return;
  await db
      .into(db.noteVersions)
      .insertOnConflictUpdate(row.copyWith(updatedAt: DateTime.now()));
}

/// Replaces the note's title and body with a version's. The current state
/// is saved first as "Before restoring" (unless it already equals that
/// version), so a restore can itself be undone. The note is stamped "now",
/// so it syncs, and an open editor absorbs it. Returns false if the
/// version or note no longer exists.
///
/// A locked note (or version) needs [lock] with its key unlocked: both
/// sides are decrypted to compare, and the restored body is encrypted for
/// the note again with the current key (a locked note stays locked, an
/// unlocked one stays unlocked). Throws [NoteLockedException] — before
/// changing anything — if a key isn't unlocked, so the caller can ask.
Future<bool> restoreNoteVersion(
  AppDatabase db,
  String versionId, {
  NoteLockService? lock,
}) => db.transaction(() async {
  final version = await (db.select(
    db.noteVersions,
  )..where((v) => v.id.equals(versionId))).getSingleOrNull();
  if (version == null) return false;
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(version.noteId))).getSingleOrNull();
  if (note == null) return false;

  var body = version.content;
  if (isLockedContent(version.content) || isLockedContent(note.content)) {
    if (lock == null) throw const NoteLockedException();
    final versionText = await lock.decryptBody(note.id, version.content);
    final noteText = await lock.decryptBody(note.id, note.content);
    if (version.title == note.title && _sameContent(versionText, noteText)) {
      return true;
    }
    body = isLockedContent(note.content)
        ? await lock.encryptBody(note.id, versionText)
        : versionText;
  } else if (sameBody(version.title, version.content, note)) {
    return true;
  }
  await saveNoteVersion(db, note.id, label: beforeRestoringLabel);
  await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
    NotesCompanion(
      title: Value(version.title),
      content: Value(body),
      updatedAt: Value(DateTime.now()),
    ),
  );
  return true;
});

/// The plain text of a note's body and of its versions, for the versions
/// screens: keyed by version id, and `note` for the note itself. A locked
/// body appears only while its key is unlocked, so a missing entry means
/// "locked". Refreshes when notes lock or unlock.
final versionTextsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, noteId) async {
      final lock = ref.watch(noteLockServiceProvider);
      final versions =
          ref.watch(noteVersionsProvider(noteId)).value ?? const [];
      final note = ref.watch(versionNoteProvider(noteId)).value;
      final out = <String, String>{};
      Future<void> add(String key, String content) async {
        if (!lock.canRead(content)) return;
        try {
          out[key] = await lock.decryptBody(noteId, content);
        } on Object {
          // Damaged envelope: treated as locked.
        }
      }

      if (note != null) await add('note', note.content);
      for (final v in versions) {
        await add(v.id, v.content);
      }
      return out;
    });

/// A note's versions, newest first.
final noteVersionsProvider = StreamProvider.autoDispose
    .family<List<NoteVersion>, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.noteVersions)
            ..where((v) => v.noteId.equals(noteId))
            ..orderBy([
              (v) => OrderingTerm.desc(v.createdAt),
              (v) => OrderingTerm.desc(v.updatedAt),
            ]))
          .watch();
    });

/// The note itself, for comparing against it.
final versionNoteProvider = StreamProvider.autoDispose.family<Note?, String>((
  ref,
  noteId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).watchSingleOrNull();
});

/// A note body as lines of plain text, for comparing. Stored bodies keep
/// citations (`[@key]`) and maths (`$x$`) as text already, so those read
/// as written; a sketch is "[Sketch]". Blank trailing lines are dropped.
List<String> noteLines(String content) {
  final lines = decodeNoteContent(content)
      .toPlainText()
      .replaceAll('￼', '[Sketch]')
      .split('\n');
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Words as the chapter outline counts them (citations are not words).
int noteWordCount(String content) => noteStats(editorDocument(content)).words;

enum DiffKind { same, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text);
  final DiffKind kind;
  final String text;

  @override
  String toString() =>
      '${const {DiffKind.same: ' ', DiffKind.added: '+', DiffKind.removed: '-'}[kind]}$text';
}

/// A line diff turning [before] into [after] (longest common subsequence;
/// the common head and tail are skipped first, and a rewrite too large for
/// a quadratic table is shown as all removed then all added).
List<DiffLine> diffLines(List<String> before, List<String> after) {
  var head = 0;
  while (head < before.length &&
      head < after.length &&
      before[head] == after[head]) {
    head++;
  }
  var tail = 0;
  while (tail < before.length - head &&
      tail < after.length - head &&
      before[before.length - 1 - tail] == after[after.length - 1 - tail]) {
    tail++;
  }
  final a = before.sublist(head, before.length - tail);
  final b = after.sublist(head, after.length - tail);
  final out = <DiffLine>[
    for (final l in before.take(head)) DiffLine(DiffKind.same, l),
  ];

  if (a.isEmpty || b.isEmpty || a.length * b.length > 4000000) {
    out.addAll([
      for (final l in a) DiffLine(DiffKind.removed, l),
      for (final l in b) DiffLine(DiffKind.added, l),
    ]);
  } else {
    final table = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var x = a.length - 1; x >= 0; x--) {
      for (var y = b.length - 1; y >= 0; y--) {
        table[x][y] = a[x] == b[y]
            ? table[x + 1][y + 1] + 1
            : (table[x + 1][y] >= table[x][y + 1]
                  ? table[x + 1][y]
                  : table[x][y + 1]);
      }
    }
    var x = 0, y = 0;
    while (x < a.length && y < b.length) {
      if (a[x] == b[y]) {
        out.add(DiffLine(DiffKind.same, a[x]));
        x++;
        y++;
      } else if (table[x + 1][y] >= table[x][y + 1]) {
        out.add(DiffLine(DiffKind.removed, a[x++]));
      } else {
        out.add(DiffLine(DiffKind.added, b[y++]));
      }
    }
    while (x < a.length) {
      out.add(DiffLine(DiffKind.removed, a[x++]));
    }
    while (y < b.length) {
      out.add(DiffLine(DiffKind.added, b[y++]));
    }
  }
  out.addAll([
    for (final l in after.skip(after.length - tail)) DiffLine(DiffKind.same, l),
  ]);
  return out;
}
