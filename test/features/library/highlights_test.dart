import 'dart:ui';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/library/highlights.dart';
import 'package:corplex/features/library/quote_to_note.dart';
import 'package:corplex/features/notes/note_content.dart';

void main() {
  group('lineRects', () {
    test('merges characters on the same line and splits lines', () {
      final chars = [
        const Rect.fromLTRB(10, 100, 18, 112), // line 1
        const Rect.fromLTRB(18, 101, 26, 112),
        const Rect.fromLTRB(26, 100, 26, 112), // zero-width space: skipped
        const Rect.fromLTRB(30, 100, 40, 113),
        const Rect.fromLTRB(10, 120, 20, 132), // line 2
        const Rect.fromLTRB(20, 120, 50, 132),
      ];
      final lines = lineRects(chars, const Size(100, 200));
      expect(lines, hasLength(2));
      expect(lines[0], const Rect.fromLTRB(0.1, 0.5, 0.4, 0.565));
      expect(lines[1].left, 0.1);
      expect(lines[1].right, 0.5);
    });

    test('a superscript on the same line stays on that line', () {
      final lines = lineRects([
        const Rect.fromLTRB(0, 100, 10, 112),
        const Rect.fromLTRB(10, 97, 14, 105), // footnote marker
        const Rect.fromLTRB(14, 100, 24, 112),
      ], const Size(100, 100));
      expect(lines, hasLength(1));
    });
  });

  test('rects survive encoding (rounded to 4 decimals)', () {
    final rects = [const Rect.fromLTRB(0.123456, 0.5, 0.75, 0.52)];
    final back = decodeRects(encodeRects(rects));
    expect(back.single.left, 0.1235);
    expect(back.single.bottom, 0.52);
    expect(decodeRects('garbage'), isEmpty);
  });

  test('cleanQuote rejoins hyphenated words and line breaks', () {
    expect(
      cleanQuote('The trans-\nformer relies\n  entirely on  attention.'),
      'The transformer relies entirely on attention.',
    );
  });

  test('paper page links round-trip; others are rejected', () {
    final link = paperPageLink('p-1', 12);
    expect(parsePaperPageLink(link), (paperId: 'p-1', page: 12));
    expect(parsePaperPageLink('corplex://audio/a?t=3'), isNull);
    expect(parsePaperPageLink('corplex://paper/p?page=0'), isNull);
    expect(parsePaperPageLink('https://example.com'), isNull);
  });

  group('with a database', () {
    late AppDatabase db;
    late Paper paper;

    setUp(() async {
      db = AppDatabase.inMemoryForTesting();
      await db
          .into(db.papers)
          .insert(
            PapersCompanion.insert(id: const Value('p1'), title: 'Attention'),
          );
      paper = await db.select(db.papers).getSingle();
    });
    tearDown(() => db.close());

    Future<Highlight> highlight({String? comment}) async {
      final id = await addHighlight(
        db,
        paperId: 'p1',
        pageNumber: 3,
        quote: 'Self-attention\nis key.',
        rects: const [Rect.fromLTRB(0.1, 0.2, 0.9, 0.22)],
        color: highlightInks[1],
      );
      if (comment != null) await updateHighlight(db, id, comment: comment);
      return (db.select(
        db.highlights,
      )..where((h) => h.id.equals(id))).getSingle();
    }

    test('add, recolor, comment, delete', () async {
      final h = await highlight();
      expect(h.quote, 'Self-attention is key.');
      expect(h.colorHex, colorToHex(highlightInks[1]));

      await updateHighlight(
        db,
        h.id,
        color: highlightInks[2],
        comment: '  why? ',
      );
      final updated = await db.select(db.highlights).getSingle();
      expect(updated.colorHex, colorToHex(highlightInks[2]));
      expect(updated.comment, 'why?');

      await updateHighlight(db, h.id, comment: '   ');
      expect((await db.select(db.highlights).getSingle()).comment, isNull);

      await deleteHighlight(db, h.id);
      expect(await db.select(db.highlights).get(), isEmpty);
    });

    test('deleting a paper deletes its highlights', () async {
      await highlight();
      await db.delete(db.papers).go();
      expect(await db.select(db.highlights).get(), isEmpty);
    });

    test('quoting into a new note links it to the paper', () async {
      final h = await highlight(comment: 'Central claim');
      final noteId = await quoteHighlightIntoNote(
        db,
        highlight: h,
        paper: paper,
      );

      final note = await db.select(db.notes).getSingle();
      expect(note.id, noteId);
      expect(note.title, 'Notes on Attention');
      expect(
        decodeNoteContent(note.content).toPlainText(),
        'Self-attention is key.\n— p. 3\nCentral claim\n',
      );
      expect(note.content, contains('corplex://paper/p1?page=3'));
      expect((await db.select(db.notePaperRefs).getSingle()).paperId, 'p1');
    });

    test('quoting into an existing note appends and links once', () async {
      final h = await highlight();
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: const Value('n1'),
              title: const Value('Mine'),
            ),
          );
      await quoteHighlightIntoNote(
        db,
        highlight: h,
        paper: paper,
        noteId: 'n1',
      );
      await quoteHighlightIntoNote(
        db,
        highlight: h,
        paper: paper,
        noteId: 'n1',
      );

      final text = decodeNoteContent(
        (await db.select(db.notes).getSingle()).content,
      ).toPlainText();
      expect('p. 3'.allMatches(text), hasLength(2));
      expect(await db.select(db.notePaperRefs).get(), hasLength(1));
    });

    test('saving the same page again is not an edit', () async {
      await saveLastPage(db, 'p1', 5);
      final first = await db.select(db.papers).getSingle();
      expect(first.lastPage, 5);
      await db.customStatement('DELETE FROM sync_dirty');

      await saveLastPage(db, 'p1', 5);

      final dirty = await db
          .customSelect('SELECT COUNT(*) c FROM sync_dirty')
          .getSingle();
      expect(dirty.read<int>('c'), 0);
    });
  });
}
