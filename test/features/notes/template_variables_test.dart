import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:corplex/features/notes/note_content.dart';
import 'package:corplex/features/notes/template_variables.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  // Wednesday 21 October 2026, 09:05.
  final now = DateTime(2026, 10, 21, 9, 5);

  group('expandTemplateVariables', () {
    test('date, time and title', () {
      expect(expandTemplateVariables('{{date}}', now: now), 'Oct 21, 2026');
      expect(expandTemplateVariables('{{time}}', now: now), contains('9:05'));
      expect(
        expandTemplateVariables('# {{title}}', now: now, title: 'Plan'),
        '# Plan',
      );
    });

    test('date formats use moment tokens', () {
      String f(String format) =>
          expandTemplateVariables('{{date:$format}}', now: now);
      expect(f('YYYY-MM-DD'), '2026-10-21');
      expect(f('YY/M/D'), '26/10/21');
      expect(f('dddd, MMMM D'), 'Wednesday, October 21');
      expect(f('ddd MMM DD'), 'Wed Oct 21');
      expect(f('HH:mm'), '09:05');
      expect(f('H:mm'), '9:05');
      expect(f('[Week of] D'), 'Week of 21');
    });

    test('single-digit parts pad only for the doubled tokens', () {
      final d = DateTime(2026, 3, 4, 7, 8);
      expect(
        expandTemplateVariables('{{date:MM M DD D HH H mm}}', now: d),
        '03 3 04 4 07 7 08',
      );
    });

    test('names follow the locale', () {
      expect(
        expandTemplateVariables('{{date:dddd MMMM}}', now: now, locale: 'de'),
        'Mittwoch Oktober',
      );
    });

    test('unknown variables and plain braces stay', () {
      const text = '{{weather}} {x} {{ date:YYYY }} {{title:x}}';
      expect(
        expandTemplateVariables(text, now: now),
        '{{weather}} {x} 2026 {{title:x}}',
      );
    });

    test('several variables and no variables', () {
      expect(
        expandTemplateVariables('{{date:YYYY}} / {{date:MM}}', now: now),
        '2026 / 10',
      );
      expect(expandTemplateVariables('plain', now: now), 'plain');
    });
  });

  group('expandTemplateContent', () {
    test('fills text, keeps formatting and embeds', () {
      final doc = Document.fromJson([
        {
          'insert': 'Day {{date:D}}',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
        {
          'insert': {'sketch': '{}'},
        },
        {'insert': ' for {{title}}\n'},
      ]);
      final out = decodeNoteContent(
        expandTemplateContent(encodeNoteContent(doc), now: now, title: 'Mine'),
      ).toDelta().toJson();
      expect(out[0], {
        'insert': 'Day 21',
        'attributes': {'bold': true},
      });
      expect(jsonEncode(out), contains('"sketch"'));
      expect(jsonEncode(out), contains(' for Mine'));
    });

    test('content without variables is returned unchanged', () {
      final stored = encodeNoteContent(Document()..insert(0, 'hello'));
      expect(
        identical(expandTemplateContent(stored, now: now), stored),
        isTrue,
      );
    });
  });
}
