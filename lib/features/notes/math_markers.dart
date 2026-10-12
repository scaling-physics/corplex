import 'dart:convert';

/// LaTeX maths in notes is *stored* as plain text, like citations: inline
/// `$x^2$` inside a paragraph, display maths as a paragraph that is exactly
/// `$$ \int f $$`. Only the editor sees chips and blocks: [mathToEmbeds]
/// turns the markers into embeds when a note is loaded and
/// [mathEmbedsToText] turns them back on save, so search, previews, sync
/// line-merging, Markdown, old app versions and every other consumer only
/// ever meet the LaTeX source as text.
const mathInlineType = 'math';
const mathBlockType = 'mathblock';

/// A `$…$` span found in a string.
class MathSpan {
  const MathSpan(this.start, this.end, this.latex);

  /// Offsets of the opening and past the closing `$`.
  final int start;
  final int end;
  final String latex;
}

bool _isWord(String ch) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
bool _isSpace(String ch) => RegExp(r'\s').hasMatch(ch);
bool _isDigit(String ch) => RegExp(r'[0-9]').hasMatch(ch);

/// The inline maths in [s], by Pandoc's rules so money isn't maths:
/// the opening `$` has non-space text right after it and isn't glued to a
/// preceding word or `$`; the closing `$` follows non-space text and isn't
/// followed by a digit; a `\$` is a dollar sign; spans stay on one line and
/// contain no other `$`. "$5 and $10" therefore stays text.
List<MathSpan> findInlineMath(String s) {
  final out = <MathSpan>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] != r'$') {
      i++;
      continue;
    }
    final open = i;
    final okOpen =
        (open == 0 ||
            (s[open - 1] != r'\' &&
                s[open - 1] != r'$' &&
                !_isWord(s[open - 1]))) &&
        open + 1 < s.length &&
        s[open + 1] != r'$' &&
        !_isSpace(s[open + 1]);
    if (!okOpen) {
      i++;
      continue;
    }
    var j = open + 1;
    int? close;
    while (j < s.length) {
      final ch = s[j];
      if (ch == '\n') break;
      if (ch == r'\') {
        j += 2;
        continue;
      }
      if (ch == r'$') {
        final good =
            !_isSpace(s[j - 1]) &&
            (j + 1 >= s.length || (!_isDigit(s[j + 1]) && s[j + 1] != r'$'));
        if (good) close = j;
        break;
      }
      j++;
    }
    if (close == null) {
      i++;
      continue;
    }
    out.add(MathSpan(open, close + 1, s.substring(open + 1, close)));
    i = close + 1;
  }
  return out;
}

/// The LaTeX of a line that is exactly `$$ … $$`, else null.
String? displayMathOf(String line) {
  final t = line.trim();
  if (t.length < 5 || !t.startsWith(r'$$') || !t.endsWith(r'$$')) return null;
  final body = t.substring(2, t.length - 2);
  if (body.contains(r'$$') || body.trim().isEmpty) return null;
  return body.trim();
}

/// A display-maths line for [latex] (newlines folded into spaces so the
/// equation stays one line of the note).
String displayMathMarker(String latex) =>
    '\$\$ ${latex.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim()} \$\$';

String inlineMathMarker(String latex) =>
    '\$${latex.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim()}\$';

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

/// Stored note content → the editor's form, with maths as embeds. Content
/// that isn't Delta JSON is returned unchanged.
String mathToEmbeds(String stored) {
  if (!stored.contains(r'$')) return stored;
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  var lineStart = true;
  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String) {
      out.add(op);
      lineStart = false;
      continue;
    }
    final attributes = op['attributes'];
    Map<String, Object?> make(Object value) => {
      'insert': value,
      'attributes': ?attributes,
    };
    final plain = attributes == null;
    final pieces = <Object>[]; // String or {type: latex}
    if (plain && insert.contains(r'$')) {
      // Display lines: whole lines of this op, ended by a newline in it.
      final lines = insert.split('\n');
      var atStart = lineStart;
      var pending = StringBuffer();
      for (var k = 0; k < lines.length; k++) {
        final isLast = k == lines.length - 1;
        final display = !isLast && atStart ? displayMathOf(lines[k]) : null;
        if (display != null) {
          if (pending.isNotEmpty) pieces.add(pending.toString());
          pending = StringBuffer();
          pieces.add({mathBlockType: display});
        } else {
          pending.write(lines[k]);
        }
        if (!isLast) pending.write('\n');
        atStart = true;
      }
      if (pending.isNotEmpty) pieces.add(pending.toString());
    } else {
      pieces.add(insert);
    }
    for (final piece in pieces) {
      if (piece is! String) {
        out.add(make(piece));
        continue;
      }
      final inCode = attributes is Map && attributes.containsKey('code');
      final spans = inCode ? const <MathSpan>[] : findInlineMath(piece);
      var pos = 0;
      for (final m in spans) {
        if (m.start > pos) out.add(make(piece.substring(pos, m.start)));
        out.add(make({mathInlineType: m.latex}));
        pos = m.end;
      }
      if (pos < piece.length) out.add(make(piece.substring(pos)));
    }
    lineStart = insert.endsWith('\n');
  }
  return jsonEncode(out);
}

/// The editor's content → stored form: maths embeds back to `$…$` text.
/// The result is raw Delta JSON (call before the editor's normalising
/// save step, or pass the result through it).
String mathEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$mathInlineType"') &&
      !editorContent.contains('"$mathBlockType"')) {
    return editorContent;
  }
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  final out = <Map<String, Object?>>[];
  for (final op in ops) {
    final insert = op['insert'];
    if (insert is Map && insert.containsKey(mathInlineType)) {
      out.add({
        'insert': inlineMathMarker('${insert[mathInlineType]}'),
        'attributes': ?op['attributes'],
      });
    } else if (insert is Map && insert.containsKey(mathBlockType)) {
      out.add({'insert': displayMathMarker('${insert[mathBlockType]}')});
    } else {
      out.add(op);
    }
  }
  return jsonEncode(out);
}
