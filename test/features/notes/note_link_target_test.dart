import 'dart:math';

import 'package:corplex/features/notes/note_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links to a note, a heading and a block round-trip', () {
    for (final target in const [
      NoteLinkTarget('n1'),
      NoteLinkTarget('n1', heading: 'Methods & results: 2/3 #1'),
      NoteLinkTarget('n1', block: 'a1b2c3'),
    ]) {
      final link = noteLink(
        target.noteId,
        heading: target.heading,
        block: target.block,
      );
      expect(parseNoteLinkTarget(link), target);
      // Older code reads every one of them as a link to the note.
      expect(parseNoteLink(link), 'n1');
      expect(link, startsWith('corplex://note/n1'));
    }
  });

  test('a malformed fragment is just a link to the note', () {
    expect(
      parseNoteLinkTarget('corplex://note/n1#block=no spaces'),
      const NoteLinkTarget('n1'),
    );
    expect(
      parseNoteLinkTarget('corplex://note/n1#heading='),
      const NoteLinkTarget('n1'),
    );
    expect(parseNoteLinkTarget('corplex://paper/p1'), isNull);
  });

  test('block markers and ids', () {
    expect(blockIdPattern.firstMatch('A claim. ^x7k2qa')?.group(1), 'x7k2qa');
    expect(blockIdPattern.hasMatch('Not ^a marker in the middle'), isFalse);
    expect(blockIdPattern.hasMatch('^nospace'), isFalse);
    final id = newBlockId(Random(1));
    expect(id, matches(RegExp(r'^[a-z0-9]{6}$')));
  });

  test('note embed data carries the link', () {
    final link = noteLink('n1', heading: 'Intro');
    expect(noteEmbedLink(noteEmbedData(link)), link);
    expect(noteEmbedLink('{"link":"https://x"}'), isNull);
    expect(noteEmbedLink('not json'), isNull);
  });
}
