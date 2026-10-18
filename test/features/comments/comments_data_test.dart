import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/sync_schema.dart';
import 'package:corplex/data/trash.dart';
import 'package:corplex/features/comments/comment_anchor.dart';
import 'package:corplex/features/comments/comments_data.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

String _body(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  group('locateQuote', () {
    test('exact match nearest the anchor', () {
      const text = 'cat dog cat dog cat';
      expect(locateQuote(text, 'cat', 0), (start: 0, end: 3));
      expect(locateQuote(text, 'cat', 9), (start: 8, end: 11));
      expect(locateQuote(text, 'cat', 100), (start: 16, end: 19));
    });

    test('follows the passage after edits above it', () {
      const before = 'Intro. The model fails here.';
      final anchor = before.indexOf('The model');
      const after = 'A new opening paragraph. Intro. The model fails here.';
      final s = locateQuote(after, 'The model', anchor)!;
      expect(after.substring(s.start, s.end), 'The model');
      expect(s.start, after.indexOf('The model'));
    });

    test('falls back to a case-insensitive match, then to null', () {
      expect(locateQuote('see THE MODEL now', 'the model', 0), (
        start: 4,
        end: 13,
      ));
      expect(locateQuote('nothing like it', 'the model', 0), isNull);
      expect(locateQuote('anything', '', 0), isNull);
    });

    test('displayQuote tidies embeds and blanks', () {
      expect(displayQuote(' a￼  b\n c '), 'a… b c');
    });
  });

  group('store', () {
    late AppDatabase db;
    late NoteLockService lock;
    late CommentStore store;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      lock = NoteLockService(
        db,
        crypto: NoteCrypto(iterations: 1000),
        inlineKdf: true,
      );
      store = CommentStore(db, lock);
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n'),
              title: const Value('Ch 1'),
              content: Value(_body('The hippocampus replays sequences.')),
            ),
          );
    });
    tearDown(() => db.close());

    test('sync spec lists note_comments after notes', () {
      final names = [for (final t in syncTables) t.name];
      expect(
        names.indexOf('note_comments'),
        greaterThan(names.indexOf('notes')),
      );
    });

    test(
      'add stores quote, anchor, author; resolve, edit, delete, undo',
      () async {
        final id = await store.add(
          noteId: 'n',
          quote: 'hippocampus',
          anchor: 4,
          body: ' Define this ',
          author: ' Supervisor ',
        );
        var row = await (db.select(db.noteComments)).getSingle();
        expect(row.id, id);
        expect(row.quote, 'hippocampus');
        expect(row.anchor, 4);
        expect(row.body, 'Define this');
        expect(row.author, 'Supervisor');
        expect(row.resolved, isFalse);
        expect(await store.recentAuthors(), ['Supervisor']);

        await store.setResolved(id, true);
        row = await db.select(db.noteComments).getSingle();
        expect(row.resolved, isTrue);
        await store.setResolved(id, false);

        await store.edit(await store.view(row), body: 'Define it', author: '');
        row = await db.select(db.noteComments).getSingle();
        expect(row.body, 'Define it');
        expect(row.author, isNull);

        await store.delete(id);
        expect(await db.select(db.noteComments).get(), isEmpty);
        await store.restore(row);
        expect(
          (await db.select(db.noteComments).getSingle()).body,
          'Define it',
        );
      },
    );

    test(
      'a note in the trash takes its comments along and gets them back',
      () async {
        await store.add(
          noteId: 'n',
          quote: 'replays',
          anchor: 18,
          body: 'Cite?',
        );
        final trashId = await trashNote(db, 'n');
        expect(await db.select(db.noteComments).get(), isEmpty);
        await restoreFromTrash(db, trashId);
        final rows = await db.select(db.noteComments).get();
        expect(rows.single.quote, 'replays');
        expect(rows.single.body, 'Cite?');
        expect(rows.single.noteId, 'n');
      },
    );

    test('deleting the note deletes its comments', () async {
      await store.add(noteId: 'n', quote: 'x', anchor: 0, body: 'y');
      await (db.delete(db.notes)..where((n) => n.id.equals('n'))).go();
      expect(await db.select(db.noteComments).get(), isEmpty);
    });

    test('open counts ignore resolved comments', () async {
      final a = await store.add(noteId: 'n', quote: 'a', anchor: 0, body: '1');
      await store.add(noteId: 'n', quote: 'b', anchor: 0, body: '2');
      await store.setResolved(a, true);
      final count = db.noteComments.id.count();
      final rows =
          await (db.selectOnly(db.noteComments)
                ..addColumns([db.noteComments.noteId, count])
                ..where(db.noteComments.resolved.equals(false))
                ..groupBy([db.noteComments.noteId]))
              .get();
      expect(rows.single.read(count), 1);
      expect(openCommentsLabel(1), '1 open comment');
      expect(openCommentsLabel(3), '3 open comments');
    });

    test(
      'locked note: comments are stored encrypted, readable once unlocked',
      () async {
        await lock.setPassword('hunter22');
        await store.add(
          noteId: 'n',
          quote: 'hippocampus',
          anchor: 4,
          body: 'Plain, before locking',
        );
        await lock.lockNote('n');
        var row = await db.select(db.noteComments).getSingle();
        expect(isLockedContent(row.quote), isTrue);
        expect(isLockedContent(row.body), isTrue);
        expect(row.quote, isNot(contains('hippocampus')));

        // Adding while the key is available encrypts too.
        await store.add(
          noteId: 'n',
          quote: 'replays',
          anchor: 18,
          body: 'Secret',
        );
        for (final r in await db.select(db.noteComments).get()) {
          expect(isLockedContent(r.quote), isTrue);
          expect(isLockedContent(r.body), isTrue);
          expect(r.body, isNot(contains('Secret')));
        }
        final views = [
          for (final r in await db.select(db.noteComments).get())
            await store.view(r),
        ];
        expect(
          views.map((v) => v.body),
          containsAll(['Plain, before locking', 'Secret']),
        );

        // Locked again: unreadable, and adding is refused.
        lock.lockNow();
        expect(() => store.view(row), throwsA(isA<NoteLockedException>()));
        expect(
          () => store.add(noteId: 'n', quote: 'q', anchor: 0, body: 'b'),
          throwsA(isA<NoteLockedException>()),
        );

        // Removing the lock puts the comments back in the clear.
        expect(await lock.unlock('hunter22'), isTrue);
        await lock.removeLock('n');
        row = (await db.select(db.noteComments).get()).first;
        expect(isLockedContent(row.quote), isFalse);
        expect(
          (await db.select(db.noteComments).get()).map((r) => r.body),
          containsAll(['Plain, before locking', 'Secret']),
        );
      },
    );
  });
}
