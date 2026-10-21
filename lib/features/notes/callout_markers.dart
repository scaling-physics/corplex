import 'dart:convert';

/// Callouts are *stored* Obsidian-style: a block-quote line whose text
/// starts `[!type]`, optionally followed by a title; the quote lines after
/// it are the callout's body. Only the editor sees a chip: the marker at the
/// start of such a line becomes one inline `callout` embed (icon + label)
/// when a note is loaded ([calloutsToEmbeds]) and text again on save
/// ([calloutEmbedsToText]). The embed's data is the marker as written
/// (`[!warning]`, or `[!faq]-` with Obsidian's fold sign), so the round trip
/// is exact.
const calloutEmbedType = 'callout';

/// How a callout is coloured: the theme role it borrows.
enum CalloutTone { primary, tertiary, secondary, error }

/// The callout types that have their own look; any other word is drawn as a
/// `note`.
const calloutTypes = <String, CalloutTone>{
  'note': CalloutTone.primary,
  'info': CalloutTone.primary,
  'tip': CalloutTone.tertiary,
  'success': CalloutTone.tertiary,
  'example': CalloutTone.tertiary,
  'important': CalloutTone.secondary,
  'question': CalloutTone.secondary,
  'todo': CalloutTone.secondary,
  'warning': CalloutTone.error,
  'caution': CalloutTone.error,
  'danger': CalloutTone.error,
  'bug': CalloutTone.error,
};

/// The types the picker offers, in order.
const calloutPickerTypes = [
  'note',
  'info',
  'tip',
  'success',
  'example',
  'important',
  'question',
  'todo',
  'warning',
  'caution',
  'danger',
  'bug',
];

/// Fixed colours for exported documents (Word, PDF), which have no theme:
/// a pale `fill` and a stronger `bar` per tone, in the app's sage and clay.
({String fill, String bar}) calloutExportColors(CalloutTone tone) =>
    switch (tone) {
      CalloutTone.primary => (fill: 'E4ECE6', bar: '6A8F76'),
      CalloutTone.tertiary => (fill: 'F3E6DE', bar: 'B9805F'),
      CalloutTone.secondary => (fill: 'ECE8DF', bar: '8C8372'),
      CalloutTone.error => (fill: 'F6E1DD', bar: 'B5493E'),
    };

final _marker = RegExp(r'^\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-]?)');

/// A callout marker at the start of any line of a text (for previews).
final calloutLineMarker = RegExp(
  r'^\[!([A-Za-z][A-Za-z0-9_-]*)\][+-]?[ \t]*',
  multiLine: true,
);

/// The tone of a callout [type] (case-insensitive); unknown words read as
/// `note`.
CalloutTone calloutToneOf(String type) =>
    calloutTypes[type.toLowerCase()] ?? CalloutTone.primary;

/// The type in a marker such as `[!Warning]-`, lower-cased; null if [text]
/// isn't exactly a marker.
String? parseCalloutMarker(String text) {
  final m = _marker.firstMatch(text);
  if (m == null || m.end != text.length) return null;
  return m.group(1)!.toLowerCase();
}

String calloutMarker(String type) => '[!${type.toLowerCase()}]';

/// A callout found at the start of a line's text.
class CalloutHead {
  const CalloutHead(this.marker, this.type, this.title);

  /// The marker as written (`[!note]`, `[!faq]-`).
  final String marker;
  final String type;

  /// The rest of the line, trimmed.
  final String title;
}

/// The callout [line] (a block-quote line's text) opens, or null.
CalloutHead? parseCalloutLine(String line) {
  final m = _marker.firstMatch(line);
  if (m == null) return null;
  return CalloutHead(
    m.group(0)!,
    m.group(1)!.toLowerCase(),
    line.substring(m.end).trim(),
  );
}

/// `warning` → `Warning`, for the label when a callout has no title.
String calloutLabel(String type) =>
    type.isEmpty ? type : type[0].toUpperCase() + type.substring(1);

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  }
}

bool _quoted(Object? attrs) =>
    attrs is Map && attrs['blockquote'] != null && attrs['blockquote'] != false;

/// Stored note content → the editor's form, with each callout's marker as an
/// embed. Content that isn't Delta JSON is returned unchanged.
///
/// A line is a callout head when its newline carries the block-quote
/// attribute and its first op is text starting with a marker.
String calloutsToEmbeds(String stored) {
  if (!stored.contains('[!')) return stored;
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  var lineFirst = 0; // index in `out` of the current line's first op
  var changed = false;
  void head(int newlineIndexInOut) {
    if (lineFirst >= newlineIndexInOut) return;
    final first = out[lineFirst];
    final text = first['insert'];
    if (text is! String) return;
    final m = _marker.firstMatch(text);
    if (m == null) return;
    final attrs = first['attributes'];
    changed = true;
    out[lineFirst] = {
      'insert': {calloutEmbedType: m.group(0)!},
      'attributes': ?attrs,
    };
    if (m.end < text.length) {
      out.insert(lineFirst + 1, {
        'insert': text.substring(m.end),
        'attributes': ?attrs,
      });
    }
  }

  for (final op in ops) {
    final insert = op['insert'];
    if (insert is! String) {
      out.add(op);
      continue;
    }
    if (insert == '\n') {
      if (_quoted(op['attributes'])) head(out.length);
      out.add(op);
      lineFirst = out.length;
      continue;
    }
    final cut = insert.lastIndexOf('\n');
    if (cut < 0) {
      out.add(op);
      continue;
    }
    // Plain multi-line text: the lines inside carry no block style. The
    // last line may go on to be a quote line, so it gets an op of its own.
    final attrs = op['attributes'];
    out.add({'insert': insert.substring(0, cut + 1), 'attributes': ?attrs});
    lineFirst = out.length;
    if (cut + 1 < insert.length) {
      out.add({'insert': insert.substring(cut + 1), 'attributes': ?attrs});
    }
  }
  return changed ? jsonEncode(out) : stored;
}

/// The editor's content → stored form: callout embeds back to `[!type]`.
/// Raw Delta JSON; pass it through the editor's normalising save step.
String calloutEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$calloutEmbedType"')) return editorContent;
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  return jsonEncode([
    for (final op in ops)
      if (op['insert'] case {calloutEmbedType: final String marker})
        {'insert': marker, 'attributes': ?op['attributes']}
      else
        op,
  ]);
}
