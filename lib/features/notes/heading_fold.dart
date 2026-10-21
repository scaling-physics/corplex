import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Collapsible headings, like the sections in Apple Notes.
///
/// A collapsed section exists **only in the editor's document**. The lines
/// under a heading (up to the next heading of the same or a higher level,
/// or the end) are replaced by one `fold` block embed on a line of its own;
/// the embed carries the hidden lines as Delta JSON. Stored content never
/// holds a fold: `storedFromEditor` expands every one first (see
/// `editor_document.dart`), so saving, exports, sync and search all see the
/// whole note.
///
/// This file is the pure model: a Delta as a list of lines, and the folding
/// operations on it. `heading_fold_controller.dart` applies them to a live
/// `QuillController`.
const foldEmbedType = 'fold';

/// A toggle line starts with this (U+25B8 and a space), stored as plain
/// text: the lines under it with a greater `indent` are its children and
/// fold like the section under a heading. Everything that doesn't know
/// about toggles just sees a paragraph and indented lines.
const toggleMark = '\u25B8 ';

/// One line of a document: its content (no newline) and the attributes of
/// its newline (headings, lists, quotes… are block attributes).
class FoldLine {
  FoldLine(this.ops, this.attrs);

  final List<Operation> ops;
  final Map<String, dynamic>? attrs;

  /// Set by [expandLines] on a heading that was collapsed in the editor.
  bool folded = false;

  /// Characters in the document, newline included.
  int get length {
    var n = 1;
    for (final op in ops) {
      n += op.length ?? 0;
    }
    return n;
  }

  /// The heading level (1–6), or null.
  int? get header {
    final h = attrs?['header'];
    return h is int && h > 0 ? h : null;
  }

  /// The indent level of the line (0 when it has none).
  int get indent {
    final v = attrs?['indent'];
    return v is int ? v : 0;
  }

  /// A toggle line: a paragraph (or list item) that starts with [toggleMark].
  bool get isToggle {
    if (header != null || ops.isEmpty) return false;
    final d = ops.first.data;
    return d is String && d.startsWith(toggleMark);
  }

  /// Something that can fold the lines under it: a heading or a toggle.
  bool get isRoot => header != null || isToggle;

  /// The hidden lines when this line is a fold (a lone fold embed).
  String? get foldData {
    if (ops.length != 1) return null;
    return _foldDataOf(ops.first);
  }

  bool get isFold => foldData != null;

  /// The text, an embed being one object-replacement character (the way
  /// the editor's own plain text reads it).
  String get text {
    final b = StringBuffer();
    for (final op in ops) {
      final d = op.data;
      b.write(d is String ? d : '￼');
    }
    return b.toString();
  }

  String? _sig;

  /// Equal for equal lines (content, formatting and block attributes).
  String get signature => _sig ??= jsonEncode([
    for (final op in ops) [op.data, op.attributes],
    attrs,
  ]);
}

String? _foldDataOf(Operation op) {
  final d = op.data;
  if (d is Map && d.length == 1 && d.containsKey(foldEmbedType)) {
    final v = d[foldEmbedType];
    return v is String ? v : jsonEncode(v);
  }
  return null;
}

/// Whether [delta] has a fold embed anywhere.
bool deltaHasFolds(Delta delta) {
  for (final op in delta.toList()) {
    final d = op.data;
    if (op.isInsert && d is Map && d.containsKey(foldEmbedType)) return true;
  }
  return false;
}

List<FoldLine> parseFoldLines(Delta delta) {
  final lines = <FoldLine>[];
  var current = <Operation>[];
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    if (data is! String) {
      current.add(op);
      continue;
    }
    var start = 0;
    for (
      var at = data.indexOf('\n');
      at != -1;
      at = data.indexOf('\n', start)
    ) {
      if (at > start) {
        current.add(Operation.insert(data.substring(start, at), op.attributes));
      }
      lines.add(FoldLine(current, op.attributes));
      current = [];
      start = at + 1;
    }
    if (start < data.length) {
      current.add(Operation.insert(data.substring(start), op.attributes));
    }
  }
  if (current.isNotEmpty) lines.add(FoldLine(current, null));
  return lines;
}

Delta foldLinesToDelta(List<FoldLine> lines) {
  final delta = Delta();
  for (final line in lines) {
    for (final op in line.ops) {
      delta.insert(op.data, op.attributes);
    }
    delta.insert('\n', line.attrs);
  }
  return delta;
}

/// The fold embed that hides [lines] (a line of its own).
FoldLine foldLineFor(List<FoldLine> lines) {
  final data = jsonEncode({
    // Distinguishes two folds with equal content (a pasted copy).
    'id': _id(),
    'ops': foldLinesToDelta(lines).toJson(),
  });
  return FoldLine([
    Operation.insert({foldEmbedType: data}),
  ], null);
}

final _random = Random();
String _id() => _random.nextInt(1 << 32).toRadixString(36);

List<FoldLine> _hiddenOf(String data) {
  try {
    final json = jsonDecode(data);
    final ops = json is Map ? json['ops'] : json;
    return parseFoldLines(Delta.fromJson(ops as List));
  } catch (_) {
    return const [];
  }
}

/// The lines a fold hides (one level).
List<FoldLine> foldHiddenLines(String data) => _hiddenOf(data);

/// [lines] with every fold put back, nested ones too. A heading that sat
/// right above a fold is flagged [FoldLine.folded] in the result. A fold
/// embed that isn't on a line of its own (a broken structure) is expanded
/// in place, the text around it kept on lines of their own: nothing is
/// ever dropped.
List<FoldLine> expandLines(List<FoldLine> lines) {
  final out = <FoldLine>[];
  for (final line in lines) {
    final data = line.foldData;
    if (data != null) {
      if (out.isNotEmpty && out.last.isRoot) out.last.folded = true;
      out.addAll(expandLines(_hiddenOf(data)));
      continue;
    }
    if (!line.ops.any((op) => _foldDataOf(op) != null)) {
      out.add(FoldLine(line.ops, line.attrs));
      continue;
    }
    var run = <Operation>[];
    for (final op in line.ops) {
      final d = _foldDataOf(op);
      if (d == null) {
        run.add(op);
        continue;
      }
      if (run.isNotEmpty) out.add(FoldLine(run, null));
      run = [];
      out.addAll(expandLines(_hiddenOf(d)));
    }
    out.add(FoldLine(run, line.attrs));
  }
  return out;
}

/// The whole note as a Delta, every fold expanded. Not normalised: build a
/// `Document` from it to merge adjacent runs.
Delta unfoldDelta(Delta live) => deltaHasFolds(live)
    ? foldLinesToDelta(expandLines(parseFoldLines(live)))
    : live;

/// The index of the end of the section under the heading at [i]: the first
/// later heading of the same or a higher level, else the end.
int sectionEnd(List<FoldLine> lines, int i) {
  var j = i + 1;
  if (lines[i].header == null) {
    // A toggle: the lines after it that are indented deeper (a fold among
    // them is a collapsed part of its children).
    final base = lines[i].indent;
    while (j < lines.length && (lines[j].isFold || lines[j].indent > base)) {
      j++;
    }
    return j;
  }
  final level = lines[i].header!;
  while (j < lines.length) {
    final h = lines[j].header;
    if (h != null && h <= level) break;
    j++;
  }
  return j;
}

/// Whether the heading at [i] has lines under it to hide (and isn't
/// already collapsed).
bool canCollapse(List<FoldLine> lines, int i) {
  if (!lines[i].isRoot) return false;
  if (i + 1 < lines.length && lines[i + 1].isFold) return false;
  return sectionEnd(lines, i) > i + 1;
}

/// [lines] with the section under the heading at [i] hidden, or null.
List<FoldLine>? collapseLine(List<FoldLine> lines, int i) {
  if (!canCollapse(lines, i)) return null;
  final end = sectionEnd(lines, i);
  return [
    ...lines.sublist(0, i + 1),
    foldLineFor(lines.sublist(i + 1, end)),
    ...lines.sublist(end),
  ];
}

/// [lines] with the fold at [i] put back (one level), or null if it isn't
/// a fold.
List<FoldLine>? expandLine(List<FoldLine> lines, int i) {
  final data = lines[i].foldData;
  if (data == null) return null;
  return [...lines.sublist(0, i), ..._hiddenOf(data), ...lines.sublist(i + 1)];
}

/// A heading in the whole note: where to find it again after the note is
/// reloaded.
class FoldHeading {
  const FoldHeading(this.line, this.level, this.text, this.occurrence);
  final FoldLine line;
  final int level;
  final String text;

  /// How many headings with the same text come before it.
  final int occurrence;
}

/// Every heading of [full] (a note with no folds), in order.
List<FoldHeading> headingsOf(List<FoldLine> full) {
  final seen = <String, int>{};
  return [
    for (final line in full)
      if (line.isRoot)
        FoldHeading(
          line,
          line.header ?? 7,
          line.text,
          seen[line.text] = (seen[line.text] ?? -1) + 1,
        ),
  ];
}

/// A stable, opaque name for a heading, kept per device to restore folds.
/// Hashed with the note id so a locked note's headings never sit in
/// preferences as text.
String foldFingerprint(String noteId, String text, int occurrence) {
  final bytes = const DartSha256()
      .hashSync(utf8.encode('$noteId\u0000$text\u0000$occurrence'))
      .bytes;
  final b = StringBuffer();
  for (final v in bytes.take(12)) {
    b.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// The fingerprints of the headings that are collapsed in [live].
Set<String> collapsedFingerprints(Delta live, String noteId) {
  final full = expandLines(parseFoldLines(live));
  return {
    for (final h in headingsOf(full))
      if (h.line.folded) foldFingerprint(noteId, h.text, h.occurrence),
  };
}

/// [full] (no folds) with the sections named by [keys] collapsed. Later
/// headings go first, so a collapsed section holds the ones inside it as
/// folds of their own and expanding it shows them still collapsed.
///
/// [protectOffset] (an offset in [full]) and [protectTail] keep sections
/// open: the one a selection is about to land in, and those running to the
/// end of the note (where a quote is about to be appended).
List<FoldLine> applyFoldKeys(
  List<FoldLine> full,
  Set<String> keys,
  String noteId, {
  int? protectOffset,
  bool protectTail = false,
}) {
  if (keys.isEmpty) return full;
  var lines = [...full];
  final headings = headingsOf(full);
  // Offsets in the unfolded note.
  final starts = <FoldLine, int>{};
  var at = 0;
  for (final l in full) {
    starts[l] = at;
    at += l.length;
  }
  for (final h in headings.reversed) {
    if (!keys.contains(foldFingerprint(noteId, h.text, h.occurrence))) continue;
    final i = lines.indexOf(h.line);
    if (i < 0 || !canCollapse(lines, i)) continue;
    final end = sectionEnd(lines, i);
    if (protectTail && end == lines.length) continue;
    if (protectOffset != null) {
      final from = starts[h.line]! + h.line.length;
      var to = from;
      for (var j = i + 1; j < end; j++) {
        to += lines[j].isFold ? foldUnfoldedLength(lines[j]) : lines[j].length;
      }
      if (protectOffset >= from && protectOffset < to) continue;
    }
    lines = collapseLine(lines, i)!;
  }
  return lines;
}

int foldUnfoldedLength(FoldLine fold) {
  var n = 0;
  for (final l in expandLines([fold])) {
    n += l.length;
  }
  return n;
}

/// The delta that turns the document [a] into [b] by replacing the lines
/// that differ (everything before and after stays untouched).
Delta lineReplacement(List<FoldLine> a, List<FoldLine> b) {
  var p = 0;
  while (p < a.length && p < b.length && a[p].signature == b[p].signature) {
    p++;
  }
  var s = 0;
  while (s < a.length - p &&
      s < b.length - p &&
      a[a.length - 1 - s].signature == b[b.length - 1 - s].signature) {
    s++;
  }
  var offset = 0;
  for (var i = 0; i < p; i++) {
    offset += a[i].length;
  }
  var removed = 0;
  for (var i = p; i < a.length - s; i++) {
    removed += a[i].length;
  }
  final inserted = foldLinesToDelta(b.sublist(p, b.length - s));
  if (removed == 0 && inserted.isEmpty) return Delta();
  final delta = Delta();
  if (offset > 0) delta.retain(offset);
  for (final op in inserted.toList()) {
    delta.insert(op.data, op.attributes);
  }
  if (removed > 0) delta.delete(removed);
  return delta;
}
