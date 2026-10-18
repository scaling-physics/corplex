import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/read_aloud/listening_text.dart';

void main() {
  group('cleanPagesForListening', () {
    test('joins hyphenated line breaks and wrapped lines', () {
      final out = cleanPagesForListening([
        'We ran the exper-\niment twice and\nrecorded the results.',
      ]);
      expect(
        out.single,
        'We ran the experiment twice and recorded the results.',
      );
    });

    test('keeps a real hyphen before a capital', () {
      final out = cleanPagesForListening(['A well-\nKnown result.']);
      expect(out.single, isNot(contains('wellKnown')));
    });

    test('drops repeated headers, footers and page numbers', () {
      const words = ['', 'alpha', 'beta', 'gamma', 'delta'];
      final pages = [
        for (var i = 1; i <= 4; i++)
          'Journal of Tests 12 (2020)\nSmith et al. $i\nFirst line of ${words[i]} page.\nSecond line of ${words[i]} text.\nThird line of ${words[i]} text.\nFourth line of ${words[i]} text.\n$i',
      ];
      final out = cleanPagesForListening(pages);
      for (var i = 0; i < 4; i++) {
        expect(out[i], startsWith('First line of ${words[i + 1]} page.'));
        expect(out[i], isNot(contains('Journal')));
        expect(out[i], isNot(contains('Smith')));
        expect(out[i], endsWith('${words[i + 1]} text.'));
      }
    });

    test('keeps a number that is part of a sentence', () {
      final out = cleanPagesForListening([
        'First line of the paper.\nWe tested 42 mice.\nMore text follows.',
      ]);
      expect(out.single, contains('42 mice'));
    });

    test('stops at the references heading, on its page and after', () {
      final out = cleanPagesForListening([
        'Intro text.',
        'Discussion here.\nReferences\n[1] Smith. A paper.',
        '[2] Jones. Another paper.',
      ]);
      expect(out[0], 'Intro text.');
      expect(out[1], 'Discussion here.');
      expect(out[2], '');
    });

    test('numbered Bibliography heading also cuts', () {
      final out = cleanPagesForListening([
        'Body.\n7. Bibliography\nSmith 2001.',
      ]);
      expect(out.single, 'Body.');
    });

    test('a heading line gets a pause before the text', () {
      final out = cleanPagesForListening([
        '1 Introduction\nWe study mice in the lab.',
      ]);
      expect(out.single, '1 Introduction. We study mice in the lab.');
    });
  });

  group('splitSentences', () {
    test('splits plain sentences', () {
      expect(splitSentences('One two. Three four! Five six? Seven.'), [
        'One two.',
        'Three four!',
        'Five six?',
        'Seven.',
      ]);
    });

    test('does not split et al., Fig. or initials', () {
      expect(
        splitSentences(
          'Smith et al. Reported it in Fig. 2 and J. Doe agreed. Next one.',
        ),
        ['Smith et al. Reported it in Fig. 2 and J. Doe agreed.', 'Next one.'],
      );
    });

    test('does not split decimals', () {
      expect(splitSentences('The mean was 3.14 overall. Done.'), [
        'The mean was 3.14 overall.',
        'Done.',
      ]);
    });

    test('cuts over-long sentences at a comma', () {
      final long = '${List.filled(30, 'alpha beta,').join(' ')} end.';
      final parts = splitSentences(long, maxLength: 100);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.length <= 100), isTrue);
    });
  });

  test('sentencesOf tags pages', () {
    final s = sentencesOf(['Aa bb. Cc dd.', '', 'Ee ff.']);
    expect(s.map((e) => e.page), [1, 1, 3]);
  });

  test('guessLanguage', () {
    final en = List.filled(
      30,
      'the cat and the dog are in the house of that',
    ).join(' ');
    final de = List.filled(
      30,
      'der Hund und die Katze ist nicht mit dem Haus von',
    ).join(' ');
    expect(guessLanguage(en), 'en');
    expect(guessLanguage(de), 'de');
    expect(guessLanguage('short'), isNull);
  });
}
