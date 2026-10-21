import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:intl/intl.dart';

import 'note_content.dart';

/// Template variables, as in Obsidian's core Templates plugin:
/// `{{date}}`, `{{time}}`, `{{title}}` and `{{date:FORMAT}}` (moment.js
/// tokens). Anything else in `{{…}}` stays as written. Pure: the moment and
/// the language are passed in.
final _variable = RegExp(r'\{\{\s*([A-Za-z]+)\s*(?::([^{}]*))?\}\}');

// Longest first, so `MMMM` isn't read as `MM` `MM`. `[…]` escapes text.
final _formatToken = RegExp(
  r'\[([^\]]*)\]|YYYY|YY|MMMM|MMM|MM|M|dddd|ddd|DD|D|HH|H|mm',
);

/// [text] with its variables filled in for [now]. [title] is the title of
/// the note being written into. [locale] names months and days
/// (`DateFormat` needs its date data loaded, as everywhere in the app).
String expandTemplateVariables(
  String text, {
  required DateTime now,
  String title = '',
  String locale = 'en',
}) {
  if (!text.contains('{{')) return text;
  return text.replaceAllMapped(_variable, (m) {
    final name = m.group(1)!.toLowerCase();
    final arg = m.group(2);
    switch (name) {
      case 'date':
        if (arg == null) return DateFormat.yMMMd(locale).format(now);
        return formatTemplateDate(arg.trim(), now, locale: locale);
      case 'time':
        if (arg != null) return m.group(0)!;
        return DateFormat.jm(locale).format(now);
      case 'title':
        if (arg != null) return m.group(0)!;
        return title;
      default:
        return m.group(0)!;
    }
  });
}

/// [format] in moment.js tokens: `YYYY YY MM M DD D ddd dddd MMM MMMM HH H
/// mm`. Other characters pass through; `[text]` is copied literally.
String formatTemplateDate(
  String format,
  DateTime date, {
  String locale = 'en',
}) {
  return format.replaceAllMapped(_formatToken, (m) {
    final literal = m.group(1);
    if (literal != null) return literal;
    return switch (m.group(0)!) {
      'YYYY' => date.year.toString().padLeft(4, '0'),
      'YY' => (date.year % 100).toString().padLeft(2, '0'),
      'MMMM' => DateFormat.MMMM(locale).format(date),
      'MMM' => DateFormat.MMM(locale).format(date),
      'MM' => date.month.toString().padLeft(2, '0'),
      'M' => date.month.toString(),
      'dddd' => DateFormat.EEEE(locale).format(date),
      'ddd' => DateFormat.E(locale).format(date),
      'DD' => date.day.toString().padLeft(2, '0'),
      'D' => date.day.toString(),
      'HH' => date.hour.toString().padLeft(2, '0'),
      'H' => date.hour.toString(),
      'mm' => date.minute.toString().padLeft(2, '0'),
      _ => m.group(0)!,
    };
  });
}

/// Whether [stored] note content has anything to fill in.
bool hasTemplateVariables(String stored) => stored.contains('{{');

/// A note's stored [content] with the variables in its text filled in.
/// Formatting and embeds are kept; a variable split across differently
/// formatted runs is left as written. Returns [content] itself when there
/// is nothing to do.
String expandTemplateContent(
  String content, {
  required DateTime now,
  String title = '',
  String locale = 'en',
}) {
  if (!hasTemplateVariables(content)) return content;
  final delta = decodeNoteContent(content).toDelta();
  final out = Delta();
  for (final op in delta.toList()) {
    final data = op.data;
    if (op.isInsert && data is String) {
      out.insert(
        expandTemplateVariables(data, now: now, title: title, locale: locale),
        op.attributes,
      );
    } else if (op.isInsert) {
      out.insert(data, op.attributes);
    }
  }
  return encodeNoteContent(Document.fromDelta(out));
}
