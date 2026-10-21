import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import 'note_links.dart';

/// Block ids (`^abc123` at the end of a paragraph, Obsidian's syntax) are
/// *stored* as the text ` ^<id>` and shown in the editor as one `blockid`
/// embed, so the marker neither clutters the paragraph nor gets edited by
/// accident. [blockIdsToEmbeds] / [blockIdEmbedsToText] are the two sides of
/// that conversion (see `editor_document.dart`); a marker is only ever the
/// last thing on its line, so an embed typed past is moved back to the end
/// when the note is stored.
const blockIdEmbedType = 'blockid';

List<Map<String, Object?>>? _ops(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! List) return null;
    return [for (final op in decoded) (op as Map).cast<String, Object?>()];
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

final _markerAtEnd = RegExp(r' \^([A-Za-z0-9-]+)$');

/// Stored content → editor form: a line-final ` ^id` becomes a `blockid`
/// embed (carrying the text's attributes, so formatting round-trips).
String blockIdsToEmbeds(String stored) {
  if (!stored.contains(' ^')) return stored;
  final ops = _ops(stored);
  if (ops == null) return stored;
  final out = <Map<String, Object?>>[];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final insert = op['insert'];
    if (insert is! String) {
      out.add(op);
      continue;
    }
    final attributes = op['attributes'];
    final inCode = attributes is Map && attributes.containsKey('code');
    // Text before each newline in this op ends a line; the op's own end
    // does only if the next op starts one (or there is no next op).
    final nextInsert = i + 1 < ops.length ? ops[i + 1]['insert'] : null;
    final endsLine =
        i + 1 >= ops.length ||
        (nextInsert is String && nextInsert.startsWith('\n'));
    final pieces = insert.split('\n');
    for (var p = 0; p < pieces.length; p++) {
      final piece = pieces[p];
      final lineEnds = p < pieces.length - 1 || endsLine;
      final m = !inCode && lineEnds ? _markerAtEnd.firstMatch(piece) : null;
      Map<String, Object?> make(Object value) => {
        'insert': value,
        'attributes': ?attributes,
      };
      if (m != null) {
        if (m.start > 0) out.add(make(piece.substring(0, m.start)));
        out.add(make({blockIdEmbedType: m.group(1)}));
      } else if (piece.isNotEmpty) {
        out.add(make(piece));
      }
      if (p < pieces.length - 1) out.add(make('\n'));
    }
  }
  final delta = Delta();
  for (final op in out) {
    delta.insert(
      op['insert'],
      (op['attributes'] as Map?)?.cast<String, dynamic>(),
    );
  }
  return jsonEncode(delta.toJson());
}

/// The editor's content → stored form: each `blockid` embed becomes ` ^id`
/// text at the end of its line. Raw Delta JSON in and out.
String blockIdEmbedsToText(String editorContent) {
  if (!editorContent.contains('"$blockIdEmbedType"')) return editorContent;
  final ops = _ops(editorContent);
  if (ops == null) return editorContent;
  final delta = Delta();
  String? pending;
  Map<String, dynamic>? pendingAttributes;
  void flush() {
    if (pending != null) delta.insert(' ^$pending', pendingAttributes);
    pending = null;
    pendingAttributes = null;
  }

  for (final op in ops) {
    final insert = op['insert'];
    final attributes = (op['attributes'] as Map?)?.cast<String, dynamic>();
    if (insert is Map && insert[blockIdEmbedType] is String) {
      if (pending == null) {
        pending = insert[blockIdEmbedType] as String;
        pendingAttributes = attributes;
      }
      continue;
    }
    if (insert is! String) {
      delta.insert(insert, attributes);
      continue;
    }
    final pieces = insert.split('\n');
    for (var p = 0; p < pieces.length; p++) {
      if (pieces[p].isNotEmpty) delta.insert(pieces[p], attributes);
      if (p < pieces.length - 1) {
        flush();
        delta.insert('\n', attributes);
      }
    }
  }
  flush();
  return jsonEncode(delta.toJson());
}

/// [delta] without block markers, in either form (embed or ` ^id` text).
/// For exports and embedded notes, where the marker is bookkeeping.
Delta withoutBlockIds(Delta delta) {
  final ops = delta.toJson();
  final stored = blockIdEmbedsToText(jsonEncode(ops));
  final list = _ops(stored) ?? const [];
  final out = Delta();
  for (var i = 0; i < list.length; i++) {
    final insert = list[i]['insert'];
    final attributes = (list[i]['attributes'] as Map?)?.cast<String, dynamic>();
    if (insert is! String) {
      out.insert(insert, attributes);
      continue;
    }
    final next = i + 1 < list.length ? list[i + 1]['insert'] : null;
    final endsLine =
        i + 1 >= list.length || (next is String && next.startsWith('\n'));
    final pieces = insert.split('\n');
    for (var p = 0; p < pieces.length; p++) {
      var piece = pieces[p];
      if (p < pieces.length - 1 || endsLine) {
        piece = piece.replaceFirst(_markerAtEnd, '');
      }
      if (piece.isNotEmpty) out.insert(piece, attributes);
      if (p < pieces.length - 1) out.insert('\n', attributes);
    }
  }
  return out;
}

/// Text with a trailing block marker removed (` ^id` at the end).
String stripBlockId(String line) => line.replaceFirst(_markerAtEnd, '');

/// The quiet mark the editor shows for a block id: a small muted pilcrow.
class BlockIdEmbedBuilder extends EmbedBuilder {
  const BlockIdEmbedBuilder();

  @override
  String get key => blockIdEmbedType;

  @override
  bool get expanded => false;

  // Not copied as text: a pasted duplicate id would be ambiguous.
  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = embedContext.textStyle;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        '¶',
        style: style.copyWith(
          color: color.withValues(alpha: 0.45),
          fontSize: (style.fontSize ?? 16) * 0.75,
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.normal,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// [existing], or a fresh id that doesn't collide with [taken].
String blockIdFor(String? existing, Set<String> taken) {
  if (existing != null) return existing;
  var id = newBlockId();
  while (taken.contains(id)) {
    id = newBlockId();
  }
  return id;
}
