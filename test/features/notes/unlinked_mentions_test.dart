import 'dart:convert';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/notes/note_aliases.dart';
import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/note_links.dart';
import 'package:corplex/features/notes/unlinked_mentions.dart';
import 'package:corplex/features/search/search_index.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

String _text(String text) => jsonEncode([
  {'insert': '$text\n'},
]);

void main() {
  group('findUnlinkedMention', () {
    Delta d(String text) => Delta()..insert('$text\n');

    test('whole words, any case', () {
      final m = findUnlinkedMention(d('We study Hippocampus replay.'), [
        'hippocampus',
      ])!;
      expect(m.name, 'Hippocampus');
      expect(m.start, 9);
      expect(
        findUnlinkedMention(d('The hippocampal formation'), ['hippocampus']),
        isNull,
      );
      expect(findUnlinkedMention(d('mice'), ['mic']), isNull);
      expect(findUnlinkedMention(d('(mice)'), ['mice']), isNotNull);
    });

    test('names under three characters are ignored; aliases count', () {
      expect(findUnlinkedMention(d('an AI model'), ['AI']), isNull);
      final m = findUnlinkedMention(d('The mouse model'), ['Mice', 'mouse']);
      expect(m?.name, 'mouse');
    });

    test('text that is already a link does not count', () {
      final delta = Delta()
        ..insert('See ')
        ..insert('Alpha', {'link': noteLink('x')})
        ..insert(' and Alpha again\n');
      final m = findUnlinkedMention(delta, ['Alpha'])!;
      expect(m.start, 14);
    });

    test('the earliest of several names wins', () {
      final m = findUnlinkedMention(d('first Beta then Alpha'), [
        'Alpha',
        'Beta',
      ])!;
      expect(m.name, 'Beta');
    });
  });

  group('with notes', () {
    late AppDatabase db;
    late SearchIndex index;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      index = SearchIndex(db);
    });
    tearDown(() => db.close());

    Future<void> note(
      String id,
      String title,
      String content, {
      String? aliases,
    }) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(content),
            aliases: Value(aliases),
          ),
        );

    test('finds notes that name this one, with the exclusions', () async {
      await note('t', 'Hippocampus', _text('the target'), aliases: 'HPC');
      await note('a', 'Memory', _text('Replay in the hippocampus is key.'));
      await note('b', 'Via alias', _text('Recorded from HPC neurons.'));
      // Already links here.
      await note(
        'c',
        'Linked',
        jsonEncode([
          {
            'insert': 'hippocampus',
            'attributes': {'link': noteLink('t')},
          },
          {'insert': ' and hippocampus\n'},
        ]),
      );
      await note('d', 'Locked', 'corplex-locked:v1:k:AAAA');
      await note('e', 'Unrelated', _text('Nothing here.'));

      final found = await findUnlinkedMentions(db, index, 't');
      expect({for (final m in found) m.noteId}, {'a', 'b'});
      expect(found.firstWhere((m) => m.noteId == 'b').mention.name, 'HPC');
      expect(found.first.mention.snippet, contains('hippocampus'));
    });

    test('nothing for a short or empty title', () async {
      await note('t', 'AI', _text('x'));
      await note('a', 'A', _text('AI is everywhere'));
      expect(await findUnlinkedMentions(db, index, 't'), isEmpty);
    });

    test('Link turns the first mention into a note link, once', () async {
      await note('t', 'Hippocampus', _text('x'));
      await note('a', 'Memory', _text('The hippocampus and the Hippocampus.'));
      expect(await linkFirstMention(db, inNoteId: 'a', targetId: 't'), isTrue);
      final row = await (db.select(
        db.notes,
      )..where((n) => n.id.equals('a'))).getSingle();
      expect(row.content, contains(noteLink('t')));
      // Text kept as written; only the first one linked.
      final ops = decodeNoteContent(row.content).toDelta().toJson();
      final linked = [
        for (final op in ops)
          if (op['attributes']?['link'] != null) op['insert'],
      ];
      expect(linked, ['hippocampus']);
      expect(
        (await findUnlinkedMentions(db, index, 't')),
        isEmpty,
        reason: 'the note links here now',
      );
      // Each press links the next one; then there is nothing left.
      expect(await linkFirstMention(db, inNoteId: 'a', targetId: 't'), isTrue);
      expect(await linkFirstMention(db, inNoteId: 'a', targetId: 't'), isFalse);
    });
  });

  group('aliases', () {
    test('stored as a; b without duplicates', () {
      expect(parseAliases(' Mice; mouse ;;'), ['Mice', 'mouse']);
      expect(
        formatAliases(['Mice', 'mice', ' ', 'Rat; Rattus']),
        'Mice; Rat, Rattus',
      );
      expect(formatAliases([]), isNull);
      expect(parseAliases(null), isEmpty);
    });

    test('a picker match by alias reports the alias', () {
      expect(
        matchedAlias('Mouse model', ['Murine', 'Rodent'], 'rod'),
        'Rodent',
      );
      expect(matchedAlias('Mouse model', ['Murine'], 'mouse'), isNull);
      expect(matchedAlias('Mouse model', ['Murine'], ''), isNull);
    });
  });
}
