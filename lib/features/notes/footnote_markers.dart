import 'dart:convert';

import 'math_markers.dart';

/// Footnotes are *stored* as Pandoc inline footnotes — `^[text]` inside the
/// paragraph, brackets within balanced — so search, sync merging, Markdown,
/// old app versions and every other consumer only ever meet text. The text
/// may hold `[@key]` citations and `$maths$`, kept raw.
///
/// The editor shows each footnote as one inline `footnote` embed (a
/// superscript number); [footnotesToEmbeds] turns the markers into embeds
/// when a note is loaded and [footnoteEmbedsToText] turns them back on
/// save. The embed's data is the text between the brackets, exactly as
/// stored, so the round trip is exact.
const footnoteEmbedType = 'footnote';

/// A `^[…]` footnote found in a string.
class FootnoteSpan {
  const FootnoteSpan(this.start, this.end, this.text);

  /// Offsets of the `^` and past the closing `]`.
  final int start;
  final int end;

  /// The text between the brackets, as stored (escapes kept).
  final String text;
}

const _mask = '\u0000';

/// The footnotes in [s]. A footnote opens at `^[` (not `\^[`), ends at the
/// bracket that balances it, stays on one line, and is not looked for inside
/// inline maths. `[^1]` is not a footnote.
List<FootnoteSpan> findFootnotes(String s) {
  if (!s.contains('^[')) return const [];
  return _scan(s, _maskMath(s));
}

String _maskMath(String s) {
  if (!s.contains(r'$')) return s;
  final b = StringBuffer();
  var pos = 0;
  for (final m in findInlineMath(s)) {
    b.write(s.substring(pos, m.start));
    b.write(_mask * (m.end - m.start));
    pos = m.end;
  }
  b.write(s.substring(pos));
  return b.toString();
}

/// Scans [masked] (same length as [s], with code and maths blanked out) for
/// footnotes and reads their text from [s].
List<FootnoteSpan> _scan(String s, String masked) {
  final out = <FootnoteSpan>[];
  var i = 0;
  while (i < masked.length - 1) {
    if (masked[i] != '^' || masked[i + 1] != '[') {
      i++;
      continue;
    }
    if (i > 0 && masked[i - 1] == r'\') {
      i++;
      continue;
    }
    var depth = 1;
    var j = i + 2;
    int? close;
    while (j < masked.length) {
      final ch = masked[j];
      if (ch == '\n') break;
      if (ch == r'\') {
        j += 2;
        continue;
      }
      if (ch == '[') {
        depth++;
      } else if (ch == ']') {
        depth--;
        if (depth == 0) {
          close = j;
          break;
        }
      }
      j++;
    }
    if (close == null) {
      i++;
      continue;
    }
    out.add(FootnoteSpan(i, close + 1, s.substring(i + 2, close)));
    i = close + 1;
  }
  return out;
}

/// [text] made safe to sit between the brackets of a footnote: line breaks
/// become spaces and any bracket that has no partner is escaped, so a
/// stored footnote always parses back to the same text.
String balanceFootnoteText(String text) {
  final t = text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  final open = <int>[];
  final escape = <int>{};
  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (ch == r'\') {
      i++;
    } else if (ch == '[') {
      open.add(i);
    } else if (ch == ']') {
      if (open.isEmpty) {
        escape.add(i);
      } else {
        open.removeLast();
      }
    }
  }
  escape.addAll(open);
  if (escape.isEmpty) return t;
  final b = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    if (escape.contains(i)) b.write(r'\');
    b.write(t[i]);
  }
  return b.toString();
}

/// The stored marker for a footnote reading [text].
String footnoteMarker(String text) => '^[${balanceFootnoteText(text)}]';

/// A footnote's stored text as it reads: `\[` and `\]` unescaped.
String footnoteDisplayText(String text) =>
    text.replaceAllMapped(RegExp(r'\\([\[\]])'), (m) => m[1]!);

/// [text] with every footnote replaced by what [replace] says for its text
/// (previews, search text).
String replaceFootnotes(String text, String Function(String text) replace) {
  final spans = findFootnotes(text);
  if (spans.isEmpty) return text;
  final b = StringBuffer();
  var pos = 0;
  for (final f in spans) {
    b.write(text.substring(pos, f.start));
    b.write(replace(footnoteDisplayText(f.text)));
    pos = f.end;
  }
  b.write(text.substring(pos));
  return b.toString();
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

/// Stored note content → the editor's form, with footnotes as embeds.
/// Content that isn't Delta JSON is returned unchanged.
///
/// Footnotes may straddle formatting (a bold word inside one), so runs of
/// consecutive text ops are scanned as one string. Inline code and code
/// blocks are skipped, and so is the inside of `$…$`.
String footnotesToEmbeds(String stored) {
  if (!stored.contains('^[')) return stored;
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
    if (!group.any((op) => (op['insert'] as String).contains('^['))) {
      out.addAll(group);
      continue;
    }
    final text = group.map((op) => op['insert'] as String).join();
    final buf = [
      for (final op in group)
        if (op['attributes'] case final Map attrs when _truthy(attrs['code']))
          _mask * (op['insert'] as String).length
        else
          op['insert'] as String,
    ].join().split('');
    // Code-block lines: the block attribute sits on the line's newline.
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
    final spans = _scan(text, _maskMath(buf.join()));
    if (spans.isEmpty) {
      out.addAll(group);
      continue;
    }
    changed = true;
    // Cut the group's ops at the footnotes' edges; the footnote takes the
    // formatting of the op it starts in.
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
        if (f.start >= base) out.add(make({footnoteEmbedType: f.text}));
        pos = f.end < end ? f.end : end;
      }
      if (pos < end) out.add(make(s.substring(pos - base)));
      base = end;
    }
  }
  return changed ? jsonEncode(out) : stored;
}

/// The editor's content → stored form: footnote embeds back to `^[text]`.
/// Raw Delta JSON; pass it through the editor's normalising save step.
String footnoteEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$footnoteEmbedType"')) return editorContent;
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  return jsonEncode([
    for (final op in ops)
      if (op['insert'] case {footnoteEmbedType: final String text})
        {'insert': footnoteMarker(text), 'attributes': ?op['attributes']}
      else
        op,
  ]);
}
