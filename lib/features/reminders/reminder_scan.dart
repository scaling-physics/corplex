import 'dart:convert';

import '../lock/note_crypto.dart' show isLockedContent;
import '../notes/date_markers.dart';

/// A reminder derived from a note's text.
class ReminderSpec {
  const ReminderSpec({
    required this.id,
    required this.noteId,
    required this.title,
    required this.body,
    required this.when,
  });

  final int id;
  final String noteId;
  final String title;
  final String body;
  final DateTime when;

  /// Changes whenever anything the notification shows changes.
  String get fingerprint =>
      '${when.millisecondsSinceEpoch}|${title.hashCode}|${body.hashCode}';
}

/// A stable 31-bit id for a mention (FNV-1a over note id and marker).
int reminderIdFor(String noteId, String raw) {
  var h = 0x811c9dc5;
  for (final unit in '$noteId|$raw'.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

const reminderBodyLimit = 120;

/// The reminders in one note's stored [content]: mentions in the future
/// (date alone → 09:00), outside code, URLs and maths, and not in a checked
/// checklist item. A locked note has none (its body isn't readable). The
/// body is the paragraph with the marker taken out, cut to 120 characters.
List<ReminderSpec> remindersInNote({
  required String noteId,
  required String title,
  required String content,
  required DateTime now,
  String emptyBody = '',
}) {
  if (!content.contains('@{') || isLockedContent(content)) return const [];
  final List<dynamic> ops;
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return _plain(noteId, title, content, now, emptyBody);
    ops = decoded;
  } on FormatException {
    return _plain(noteId, title, content, now, emptyBody);
  }
  final out = <ReminderSpec>[];
  final seen = <int>{};
  var line = StringBuffer(); // text with code blanked (for matching)
  var shown = StringBuffer(); // the real text
  void endLine(Map? attrs) {
    final masked = line.toString();
    final text = shown.toString();
    line = StringBuffer();
    shown = StringBuffer();
    if (!masked.contains('@{')) return;
    final codeBlock = attrs != null && attrs['code-block'] != null;
    final checked = attrs != null && attrs['list'] == 'checked';
    if (codeBlock || checked) return;
    final spans = findDateMentions(masked);
    if (spans.isEmpty) return;
    var body = text;
    for (final s in spans.reversed) {
      body = body.replaceRange(s.start, s.end, '');
    }
    body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.length > reminderBodyLimit) {
      body = '${body.substring(0, reminderBodyLimit - 1).trimRight()}…';
    }
    for (final s in spans) {
      final when = s.mention.moment;
      if (!when.isAfter(now)) continue;
      final id = reminderIdFor(noteId, s.mention.raw);
      if (!seen.add(id)) continue;
      out.add(
        ReminderSpec(
          id: id,
          noteId: noteId,
          title: title,
          body: body.isEmpty ? emptyBody : body,
          when: when,
        ),
      );
    }
  }

  for (final raw in ops) {
    if (raw is! Map) continue;
    final insert = raw['insert'];
    final attrs = raw['attributes'] is Map ? raw['attributes'] as Map : null;
    if (insert is! String) {
      // A block embed (drawing, table…) ends the line it sits on.
      endLine(null);
      continue;
    }
    final inlineCode = attrs != null && attrs['code'] == true;
    for (final unit in insert.split('')) {
      if (unit == '\n') {
        endLine(attrs);
      } else {
        shown.write(unit);
        line.write(inlineCode ? '\u0000' : unit);
      }
    }
  }
  endLine(null);
  return out;
}

List<ReminderSpec> _plain(
  String noteId,
  String title,
  String content,
  DateTime now,
  String emptyBody,
) {
  // Content that isn't Delta JSON: treat it as plain text, line by line.
  return [
    for (final l in content.split('\n'))
      ...remindersInNote(
        noteId: noteId,
        title: title,
        content: jsonEncode([
          {'insert': '$l\n'},
        ]),
        now: now,
        emptyBody: emptyBody,
      ),
  ];
}
