import 'package:flutter_quill/quill_delta.dart';

import 'callout_markers.dart';
import 'heading_fold.dart';

/// Moving, duplicating, deleting and re-styling whole lines of a note, on
/// the editor's lines ([parseFoldLines] of the live document). All pure:
/// the editor turns the difference ([lineReplacement]) into one Quill
/// edit, so a move is a single undo step and every op, attribute and embed
/// of the line travels with it.

/// What "Turn into" offers.
enum TurnInto {
  text,
  title,
  heading,
  subheading,
  bullet,
  numbered,
  checklist,
  quote,
  code,
  callout,
  toggle,
}

/// The lines that move with the line at [i]: itself, plus the fold under it
/// when it is a collapsed heading or toggle, or (with [withSection]) its
/// whole section. Returns the half-open range.
(int, int) blockSpan(List<FoldLine> lines, int i, {bool withSection = false}) {
  if (lines[i].isRoot) {
    if (i + 1 < lines.length && lines[i + 1].isFold) return (i, i + 2);
    if (withSection) return (i, sectionEnd(lines, i));
  }
  return (i, i + 1);
}

/// The first line of the block that contains line [j] (a fold belongs to the
/// line above it).
int blockStart(List<FoldLine> lines, int j) =>
    lines[j].isFold && j > 0 ? j - 1 : j;

/// [lines] with the lines [from, to) moved so they start at [dest], an
/// insertion point in the original numbering (0..length), or null when that
/// is where they already are.
List<FoldLine>? moveLines(List<FoldLine> lines, int from, int to, int dest) {
  if (dest >= from && dest <= to) return null;
  final moving = lines.sublist(from, to);
  final rest = [...lines.sublist(0, from), ...lines.sublist(to)];
  final at = dest > to ? dest - moving.length : dest;
  return [...rest.sublist(0, at), ...moving, ...rest.sublist(at)];
}

/// Where the block at [i] lands when moved one block up (-1) or down (+1):
/// an insertion point for [moveLines], or null at the top or bottom.
int? stepDestination(List<FoldLine> lines, int i, int by, {int? spanEnd}) {
  final (from, to) = (i, spanEnd ?? blockSpan(lines, i).$2);
  if (by < 0) {
    if (from == 0) return null;
    return blockStart(lines, from - 1);
  }
  if (to >= lines.length) return null;
  return blockSpan(lines, to).$2;
}

/// A copy of the lines [from, to) put right after them. A fold inside is
/// given a fresh id (two folds with the same one count as a paste).
List<FoldLine> duplicateLines(List<FoldLine> lines, int from, int to) {
  final copy = <FoldLine>[];
  for (final l in lines.sublist(from, to)) {
    final data = l.foldData;
    copy.add(
      data == null
          ? FoldLine(List.of(l.ops), l.attrs == null ? null : {...l.attrs!})
          : foldLineFor(foldHiddenLines(data)),
    );
  }
  return [...lines.sublist(0, to), ...copy, ...lines.sublist(to)];
}

/// [lines] without [from, to); an empty paragraph stays if nothing would.
List<FoldLine> deleteLines(List<FoldLine> lines, int from, int to) {
  final out = [...lines.sublist(0, from), ...lines.sublist(to)];
  return out.isEmpty ? [FoldLine([], null)] : out;
}

const _blockKeys = {'header', 'list', 'blockquote', 'code-block'};

/// Whether [line] can be restyled (a drawing, table or fold can't).
bool canTurnInto(FoldLine line) {
  if (line.isFold) return false;
  for (final op in line.ops) {
    final d = op.data;
    if (d is Map) {
      // Inline embeds (citations, maths, callouts…) stay in a line; block
      // embeds are alone on theirs.
      if (line.ops.length == 1 && _isBlockEmbed(d)) return false;
    }
  }
  return true;
}

bool _isBlockEmbed(Map d) =>
    d.containsKey('sketch') ||
    d.containsKey('table') ||
    d.containsKey('mathblock') ||
    d.containsKey('noteembed') ||
    d.containsKey('contents') ||
    d.containsKey(foldEmbedType);

/// [line] restyled as [kind]: its block style replaced, its text kept. A
/// callout is a quote line that starts with a `callout` embed, a toggle a
/// line that starts with [toggleMark]; leaving either takes that off.
FoldLine turnLineInto(FoldLine line, TurnInto kind) {
  final attrs = <String, dynamic>{
    for (final e in (line.attrs ?? const <String, dynamic>{}).entries)
      if (!_blockKeys.contains(e.key)) e.key: e.value,
  };
  var ops = List<Operation>.of(line.ops);
  // Take off a toggle mark or callout marker first.
  if (ops.isNotEmpty) {
    final first = ops.first;
    final d = first.data;
    if (d is String && d.startsWith(toggleMark) && kind != TurnInto.toggle) {
      final rest = d.substring(toggleMark.length);
      ops = [
        if (rest.isNotEmpty) Operation.insert(rest, first.attributes),
        ...ops.skip(1),
      ];
    } else if (d is Map &&
        d.containsKey(calloutEmbedType) &&
        kind != TurnInto.callout) {
      ops = ops.skip(1).toList();
    }
  }
  switch (kind) {
    case TurnInto.text:
      break;
    case TurnInto.title:
      attrs['header'] = 1;
    case TurnInto.heading:
      attrs['header'] = 2;
    case TurnInto.subheading:
      attrs['header'] = 3;
    case TurnInto.bullet:
      attrs['list'] = 'bullet';
    case TurnInto.numbered:
      attrs['list'] = 'ordered';
    case TurnInto.checklist:
      attrs['list'] = 'unchecked';
    case TurnInto.quote:
      attrs['blockquote'] = true;
    case TurnInto.code:
      attrs['code-block'] = 'plain';
    case TurnInto.callout:
      attrs['blockquote'] = true;
      final has =
          ops.isNotEmpty &&
          ops.first.data is Map &&
          (ops.first.data as Map).containsKey(calloutEmbedType);
      if (!has) ops.insert(0, Operation.insert({calloutEmbedType: '[!note]'}));
    case TurnInto.toggle:
      final has =
          ops.isNotEmpty &&
          ops.first.data is String &&
          (ops.first.data as String).startsWith(toggleMark);
      if (!has) ops.insert(0, Operation.insert(toggleMark));
  }
  return FoldLine(ops, attrs.isEmpty ? null : attrs);
}
