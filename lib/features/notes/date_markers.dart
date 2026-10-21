import 'dart:convert';

import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import 'math_markers.dart';

/// A date mention is *stored* as plain text — `@{2026-11-14}` or
/// `@{2026-11-14 09:30}` (ISO date, optional 24-hour time) — so search,
/// sync, Markdown and old app versions only ever meet text. The editor shows
/// it as one inline `date` embed whose data is what sits between the braces.
const dateEmbedType = 'date';

const _mask = '\u0000';

final _mention = RegExp(
  r'(?<![\w\\])@\{(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?\}',
);

/// A parsed `2026-11-14` / `2026-11-14 09:30`.
class DateMention {
  const DateMention(this.date, this.hour, this.minute);

  /// Local calendar day (midnight).
  final DateTime date;
  final int? hour;
  final int? minute;

  bool get hasTime => hour != null;

  /// When a reminder fires: the time, or 09:00 for a date alone.
  DateTime get moment =>
      DateTime(date.year, date.month, date.day, hour ?? 9, minute ?? 0);

  /// The text between the braces.
  String get raw => dateMentionRaw(date, hour: hour, minute: minute);
}

String _two(int n) => n.toString().padLeft(2, '0');

String dateMentionRaw(DateTime date, {int? hour, int? minute}) {
  final day =
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';
  return hour == null ? day : '$day ${_two(hour)}:${_two(minute ?? 0)}';
}

/// The stored marker for [raw].
String dateMentionMarker(String raw) => '@{$raw}';

/// Parses the text between the braces; null when it isn't a real date/time.
DateMention? parseDateMention(String raw) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}))?$')
      .firstMatch(raw);
  return m == null ? null : _fromMatch(m);
}

DateMention? _fromMatch(RegExpMatch m) {
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final date = DateTime(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  int? h, mi;
  if (m[4] != null) {
    h = int.parse(m[4]!);
    mi = int.parse(m[5]!);
    if (h > 23 || mi > 59) return null;
  }
  return DateMention(date, h, mi);
}

/// A mention found in a string.
class DateSpan {
  const DateSpan(this.start, this.end, this.mention);

  /// Offsets of the `@` and past the closing `}`.
  final int start;
  final int end;
  final DateMention mention;
}

String _maskOut(String s) {
  var out = s;
  if (out.contains(r'$')) {
    final b = StringBuffer();
    var pos = 0;
    for (final m in findInlineMath(out)) {
      b.write(out.substring(pos, m.start));
      b.write(_mask * (m.end - m.start));
      pos = m.end;
    }
    b.write(out.substring(pos));
    out = b.toString();
  }
  return out.replaceAllMapped(
    RegExp(r'(?:https?://|www\.)\S+'),
    (m) => _mask * m[0]!.length,
  );
}

/// The mentions in [s] (one line or more). Not inside maths or URLs, and
/// not glued to a word (emails). Callers blank code out first with `\u0000`.
List<DateSpan> findDateMentions(String s) {
  if (!s.contains('@{')) return const [];
  final out = <DateSpan>[];
  for (final m in _mention.allMatches(_maskOut(s))) {
    final parsed = _fromMatch(m);
    if (parsed != null) out.add(DateSpan(m.start, m.end, parsed));
  }
  return out;
}

/// "Today", "Tomorrow", else "Fri 14 Nov" (with the year when it isn't this
/// one), plus the time when set.
String dateMentionLabel(AppLocalizations l10n, DateMention m, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime.utc(
    m.date.year,
    m.date.month,
    m.date.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  final locale = l10n.localeName;
  final day = switch (days) {
    0 => l10n.remindersToday,
    1 => l10n.remindersTomorrow,
    _ =>
      (m.date.year == today.year
              ? DateFormat('EEE d MMM', locale)
              : DateFormat('EEE d MMM y', locale))
          .format(m.date),
  };
  if (!m.hasTime) return day;
  return '$day ${DateFormat.Hm(locale).format(DateTime(2000, 1, 1, m.hour!, m.minute!))}';
}

/// English text for exports.
String dateMentionExportText(DateMention m) {
  final day = DateFormat('EEE d MMM y', 'en_US').format(m.date);
  return m.hasTime ? '$day ${_two(m.hour!)}:${_two(m.minute!)}' : day;
}

/// Is the mention overdue? A time passes at that time, a date at midnight.
bool dateMentionPast(DateMention m, DateTime now) {
  if (m.hasTime) return m.moment.isBefore(now);
  return m.date.isBefore(DateTime(now.year, now.month, now.day));
}

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

bool _truthy(Object? v) => v != null && v != false;

/// Stored note content → editor form, mentions as `date` embeds. Runs of
/// consecutive text ops are scanned as one string (a mention may straddle
/// formatting); inline code and code blocks are skipped.
String dateMentionsToEmbeds(String stored) {
  if (!stored.contains('@{')) return stored;
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  var changed = false;
  var i = 0;
  while (i < ops.length) {
    if (ops[i]['insert'] is! String) {
      out.add(ops[i]);
      i++;
      continue;
    }
    var j = i;
    while (j < ops.length && ops[j]['insert'] is String) {
      j++;
    }
    final group = ops.sublist(i, j);
    i = j;
    if (!group.any((op) => (op['insert'] as String).contains('@{'))) {
      out.addAll(group);
      continue;
    }
    final buf = [
      for (final op in group)
        if (op['attributes'] case final Map attrs when _truthy(attrs['code']))
          _mask * (op['insert'] as String).length
        else
          op['insert'] as String,
    ].join().split('');
    var at = 0;
    var lineStart = 0;
    for (final op in group) {
      final s = op['insert'] as String;
      final attrs = op['attributes'];
      final block = attrs is Map && _truthy(attrs['code-block']);
      for (var k = 0; k < s.length; k++) {
        if (s[k] != '\n') continue;
        if (block) {
          for (var m = lineStart; m < at + k; m++) {
            buf[m] = _mask;
          }
        }
        lineStart = at + k + 1;
      }
      at += s.length;
    }
    final spans = findDateMentions(buf.join());
    if (spans.isEmpty) {
      out.addAll(group);
      continue;
    }
    changed = true;
    var base = 0;
    for (final op in group) {
      final s = op['insert'] as String;
      final attrs = op['attributes'];
      Map<String, Object?> make(Object value) => {
        'insert': value,
        'attributes': ?attrs,
      };
      final end = base + s.length;
      var pos = base;
      for (final f in spans) {
        if (f.end <= base || f.start >= end) continue;
        if (f.start > pos) {
          out.add(make(s.substring(pos - base, f.start - base)));
        }
        if (f.start >= base) {
          out.add(make({dateEmbedType: f.mention.raw}));
        }
        pos = f.end < end ? f.end : end;
      }
      if (pos < end) out.add(make(s.substring(pos - base)));
      base = end;
    }
  }
  return changed ? jsonEncode(out) : stored;
}

/// The editor's content → stored form: `date` embeds back to `@{…}`.
String dateMentionEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$dateEmbedType"')) return editorContent;
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  return jsonEncode([
    for (final op in ops)
      if (op['insert'] case {dateEmbedType: final String raw})
        {'insert': dateMentionMarker(raw), 'attributes': ?op['attributes']}
      else
        op,
  ]);
}
