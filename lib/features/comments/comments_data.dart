import 'dart:ui' show Locale;

import 'package:flutter_riverpod/legacy.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/l10n.dart';
import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../lock/note_lock_service.dart';

/// A note's comments as the editor and panel use them: [quote], [body] in
/// the clear (decrypted if the note is locked), newest first.
class CommentView {
  const CommentView(this.row, this.quote, this.body);

  final NoteComment row;
  final String quote;
  final String body;

  String get id => row.id;
  bool get resolved => row.resolved;
  String? get author => row.author;
  DateTime get createdAt => row.createdAt;
  int get anchor => row.anchor;
}

/// Reads and writes comments. For a **locked note the quote and body are
/// stored encrypted** with the notes key, bound to the note id, exactly
/// like bodies (`encryptBody`): a comment quotes the note's text, so it
/// must not sit in the clear beside a locked body. The author, the
/// anchor offset and the resolved flag stay plain (like titles).
class CommentStore {
  CommentStore(this.db, this.lock);

  final AppDatabase db;
  final NoteLockService lock;

  Future<bool> _noteLocked(String noteId) async {
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(noteId))).getSingleOrNull();
    return note != null && isLockedContent(note.content);
  }

  Future<String> _seal(String noteId, String text, bool locked) =>
      locked ? lock.encryptBody(noteId, text) : Future.value(text);

  /// Plain text of a stored comment field (as is when it isn't locked).
  Future<String> open(String noteId, String stored) =>
      lock.decryptBody(noteId, stored);

  Future<CommentView> view(NoteComment c) async => CommentView(
    c,
    await open(c.noteId, c.quote),
    await open(c.noteId, c.body),
  );

  /// Adds a comment; returns its id. Throws [NoteLockedException] when the
  /// note is locked and its key isn't unlocked.
  Future<String> add({
    required String noteId,
    required String quote,
    required int anchor,
    required String body,
    String? author,
  }) async {
    final locked = await _noteLocked(noteId);
    final id = const Uuid().v4();
    final trimmedAuthor = author?.trim();
    await db
        .into(db.noteComments)
        .insert(
          NoteCommentsCompanion.insert(
            id: Value(id),
            noteId: noteId,
            quote: Value(await _seal(noteId, quote, locked)),
            anchor: Value(anchor),
            body: Value(await _seal(noteId, body.trim(), locked)),
            author: Value(
              trimmedAuthor == null || trimmedAuthor.isEmpty
                  ? null
                  : trimmedAuthor,
            ),
          ),
        );
    return id;
  }

  Future<void> edit(
    CommentView c, {
    required String body,
    String? author,
  }) async {
    final locked = await _noteLocked(c.row.noteId);
    final a = author?.trim();
    await (db.update(db.noteComments)..where((r) => r.id.equals(c.id))).write(
      NoteCommentsCompanion(
        body: Value(await _seal(c.row.noteId, body.trim(), locked)),
        author: Value(a == null || a.isEmpty ? null : a),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setResolved(String id, bool resolved) =>
      (db.update(db.noteComments)..where((r) => r.id.equals(id))).write(
        NoteCommentsCompanion(
          resolved: Value(resolved),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> delete(String id) =>
      (db.delete(db.noteComments)..where((r) => r.id.equals(id))).go();

  /// Puts a deleted comment back (Undo). Stamped now, or the restored row
  /// would lose to the server's delete marker on last-write-wins.
  Future<void> restore(NoteComment row) => db
      .into(db.noteComments)
      .insertOnConflictUpdate(row.copyWith(updatedAt: DateTime.now()));

  /// Authors used before, most recent first (suggestions for "From").
  Future<List<String>> recentAuthors({int limit = 5}) async {
    final rows =
        await (db.select(db.noteComments)
              ..where((c) => c.author.isNotNull())
              ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
            .get();
    final seen = <String>{};
    final out = <String>[];
    for (final r in rows) {
      final a = r.author!;
      if (seen.add(a.toLowerCase())) out.add(a);
      if (out.length >= limit) break;
    }
    return out;
  }
}

final commentStoreProvider = Provider<CommentStore>(
  (ref) => CommentStore(
    ref.watch(databaseProvider),
    ref.watch(noteLockServiceProvider),
  ),
);

/// Raw comment rows of a note, newest first.
final noteCommentRowsProvider = StreamProvider.autoDispose
    .family<List<NoteComment>, String>((ref, noteId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.noteComments)
            ..where((c) => c.noteId.equals(noteId))
            ..orderBy([
              (c) => OrderingTerm.desc(c.createdAt),
              (c) => OrderingTerm.desc(c.id),
            ]))
          .watch();
    });

/// Open (unresolved) comments per note; notes without any are absent.
final openCommentCountsProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final count = db.noteComments.id.count();
  final query = db.selectOnly(db.noteComments)
    ..addColumns([db.noteComments.noteId, count])
    ..where(db.noteComments.resolved.equals(false))
    ..groupBy([db.noteComments.noteId]);
  return query.watch().map(
    (rows) => {
      for (final r in rows) r.read(db.noteComments.noteId)!: r.read(count)!,
    },
  );
});

/// A note whose comments panel should open as soon as its editor shows
/// (set by the project page; the editor takes and clears it).
final pendingCommentsPanelProvider = StateProvider<String?>((ref) => null);

String openCommentsLabel(int n, [AppLocalizations? l10n]) =>
    (l10n ?? lookupAppLocalizations(const Locale('en'))).commentsOpenCount(n);
