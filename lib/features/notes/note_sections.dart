import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../data/database.dart';
import '../lock/note_crypto.dart' show isLockedContent;
import 'block_ids.dart';
import 'editor_document.dart';
import 'note_content.dart';
import 'note_links.dart';

/// One line of a note, as the editor counts it: [start] is its offset, an
/// embed is one character, and the newline is not part of [length].
class DocLine {
  const DocLine({
    required this.start,
    required this.length,
    required this.text,
    required this.attrs,
    this.blockId,
  });

  final int start;
  final int length;

  /// The line's text without its block id; an embed reads `￼`.
  final String text;

  /// The newline's attributes: the line's block style.
  final Map<String, dynamic> attrs;

  /// The line's block id, from a `blockid` embed or a stored ` ^id` ending.
  final String? blockId;

  int get end => start + length;

  /// 1..3 for a heading, else null.
  int? get headingLevel {
    final h = attrs['header'];
    return h is int ? h : null;
  }

  bool get isHeading => headingLevel != null;

  /// A line with something to say (not blank, not only embeds).
  bool get hasText => text.replaceAll('￼', '').trim().isNotEmpty;

  /// The line as a selection in the editor's document (without the newline).
  TextSelection get selection =>
      TextSelection(baseOffset: start, extentOffset: end);
}

/// The lines of [delta] (editor form or stored form: a block id is read
/// either way).
List<DocLine> docLines(Delta delta) {
  final lines = <DocLine>[];
  final buffer = StringBuffer();
  var offset = 0;
  var lineStart = 0;
  var length = 0;
  String? blockId;

  void close(Map<String, dynamic> attrs) {
    var text = buffer.toString();
    var id = blockId;
    if (id == null) {
      final m = blockIdPattern.firstMatch(text);
      if (m != null) {
        id = m.group(1);
        text = text.substring(0, m.start);
      }
    }
    lines.add(
      DocLine(
        start: lineStart,
        length: length,
        text: text,
        attrs: attrs,
        blockId: id,
      ),
    );
    buffer.clear();
    blockId = null;
    length = 0;
  }

  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    if (data is Map) {
      if (data[blockIdEmbedType] case final String id) {
        blockId = id;
      } else {
        buffer.write('￼');
      }
      length++;
      offset++;
      continue;
    }
    final attrs = op.attributes ?? const <String, dynamic>{};
    for (final unit in (data as String).split('\n').indexed) {
      final (i, piece) = unit;
      if (i > 0) {
        close(attrs);
        offset++;
        lineStart = offset;
      }
      buffer.write(piece);
      length += piece.length;
      offset += piece.length;
    }
  }
  if (length > 0) close(const {});
  return lines;
}

/// A heading of a note.
class NoteHeading {
  const NoteHeading(this.text, this.level, this.offset);
  final String text;
  final int level;
  final int offset;
}

List<NoteHeading> headingsOf(List<DocLine> lines) => [
  for (final l in lines)
    if (l.isHeading && l.text.trim().isNotEmpty)
      NoteHeading(l.text.trim(), l.headingLevel!, l.start),
];

/// The first heading whose text matches [heading] (case-insensitive,
/// trimmed).
DocLine? findHeadingLine(List<DocLine> lines, String heading) {
  final want = heading.trim().toLowerCase();
  for (final l in lines) {
    if (l.isHeading && l.text.trim().toLowerCase() == want) return l;
  }
  return null;
}

DocLine? findBlockLine(List<DocLine> lines, String blockId) {
  for (final l in lines) {
    if (l.blockId == blockId) return l;
  }
  return null;
}

/// The lines a reader could link to as a paragraph: text lines that aren't
/// headings.
List<DocLine> paragraphsOf(List<DocLine> lines) => [
  for (final l in lines)
    if (l.hasText && !l.isHeading) l,
];

/// What the editor selects when a link to [target] is opened in [lines]
/// (the heading or paragraph line), or null when it isn't there.
TextSelection? selectionForTarget(List<DocLine> lines, NoteLinkTarget target) {
  final line = target.heading != null
      ? findHeadingLine(lines, target.heading!)
      : target.block != null
      ? findBlockLine(lines, target.block!)
      : null;
  return line?.selection;
}

/// [selectionForTarget] for stored [content] (read in the editor's form, so
/// the offsets are the editor's).
TextSelection? selectionInContent(String content, NoteLinkTarget target) =>
    selectionForTarget(docLines(editorDocument(content).toDelta()), target);

/// The part of a note that a link or embed names: the whole note, a heading
/// with everything under it (to the next heading of the same or a higher
/// level), or one paragraph. Block markers are removed. Null when the
/// heading or block is not in the note.
Delta? sectionOf(Delta delta, NoteLinkTarget? target) {
  final bare = withoutBlockIds(delta);
  if (target == null || (target.heading == null && target.block == null)) {
    return bare;
  }
  // Offsets differ once markers are gone, so find the lines in the
  // original and cut the cleaned copy by line number.
  final lines = docLines(delta);
  final clean = docLines(bare);
  int? index;
  if (target.heading != null) {
    final line = findHeadingLine(lines, target.heading!);
    if (line != null) index = lines.indexOf(line);
  } else if (target.block != null) {
    final line = findBlockLine(lines, target.block!);
    if (line != null) index = lines.indexOf(line);
  }
  if (index == null || index >= clean.length) return null;
  var last = index;
  if (target.heading != null) {
    final level = clean[index].headingLevel!;
    for (var i = index + 1; i < clean.length; i++) {
      final l = clean[i].headingLevel;
      if (l != null && l <= level) break;
      last = i;
    }
  }
  final from = clean[index].start;
  final to = clean[last].end + 1; // through the newline
  final total = bare.toList().fold<int>(0, (a, op) => a + (op.length ?? 0));
  return bare.slice(from, to > total ? total : to);
}

/// A note's stored content with each `noteembed` replaced by the embedded
/// note's section (read from [db]), recursively to [maxDepth] levels. A note
/// already being expanded isn't expanded again (cycles), a locked or missing
/// target leaves nothing, and block markers in the embedded text are
/// dropped. Stored form in, stored form out.
Future<String> inlineNoteEmbeds(
  AppDatabase db,
  String content, {
  Set<String> expanding = const {},
  int maxDepth = 3,
}) async {
  if (!content.contains('"$noteEmbedType"')) return content;
  final ops = decodeNoteContent(content).toDelta().toList();
  final out = Delta();
  var atLineStart = true;
  var skipNewline = false;
  for (final op in ops) {
    if (!op.isInsert) continue;
    final data = op.data;
    if (data is Map && data[noteEmbedType] is String) {
      final link = noteEmbedLink(data[noteEmbedType] as String);
      final target = link == null ? null : parseNoteLinkTarget(link);
      Delta? section;
      if (target != null &&
          maxDepth > 0 &&
          !expanding.contains(target.noteId)) {
        final note = await (db.select(
          db.notes,
        )..where((n) => n.id.equals(target.noteId))).getSingleOrNull();
        if (note != null && !isLockedContent(note.content)) {
          final inner = await inlineNoteEmbeds(
            db,
            note.content,
            expanding: {...expanding, target.noteId},
            maxDepth: maxDepth - 1,
          );
          section = sectionOf(decodeNoteContent(inner).toDelta(), target);
        }
      }
      if (section != null) {
        if (!atLineStart) out.insert('\n');
        for (final inner in section.toList()) {
          out.insert(inner.data, inner.attributes);
        }
        atLineStart = true;
      }
      skipNewline = true;
      continue;
    }
    var attrs = op.attributes;
    if (data is String) {
      var text = data;
      if (skipNewline && text.startsWith('\n')) text = text.substring(1);
      skipNewline = false;
      if (text.isEmpty) continue;
      out.insert(text, attrs);
      atLineStart = text.endsWith('\n');
    } else {
      skipNewline = false;
      out.insert(data, attrs);
      atLineStart = false;
    }
  }
  return jsonEncode(out.toJson());
}

/// Appends a block id to the line starting at [lineStart] of an editor-form
/// [document] (an offset in [editorDocument]'s numbering) unless it has one,
/// and returns the id.
String assignBlockIdIn(Document document, int lineStart) {
  final lines = docLines(document.toDelta());
  final line = lines.firstWhere(
    (l) => l.start == lineStart,
    orElse: () => throw ArgumentError('No line at $lineStart'),
  );
  if (line.blockId != null) return line.blockId!;
  final taken = {
    for (final l in lines)
      if (l.blockId != null) l.blockId!,
  };
  final id = blockIdFor(null, taken);
  document.insert(line.end, Embeddable(blockIdEmbedType, id));
  return id;
}

/// Writes a block id onto the paragraph starting at [lineStart] (an offset
/// in the editor's numbering of the stored note) of note [noteId] and
/// returns it, or null when the note can't be written: missing, or locked
/// and [decrypt]/[encrypt] not given (or failing). Existing ids are reused.
Future<String?> assignBlockIdInNote(
  AppDatabase db,
  String noteId,
  int lineStart, {
  Future<String> Function(String content)? decrypt,
  Future<String> Function(String body)? encrypt,
}) async {
  final note = await (db.select(
    db.notes,
  )..where((n) => n.id.equals(noteId))).getSingleOrNull();
  if (note == null) return null;
  final locked = isLockedContent(note.content);
  if (locked && (decrypt == null || encrypt == null)) return null;
  final String body;
  try {
    body = locked ? await decrypt!(note.content) : note.content;
  } on Object {
    return null;
  }
  final document = editorDocument(body);
  final String id;
  try {
    id = assignBlockIdIn(document, lineStart);
  } on ArgumentError {
    return null;
  }
  final changed = storedFromEditor(document);
  if (changed != body) {
    final written = locked ? await encrypt!(changed) : changed;
    await (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(content: Value(written), updatedAt: Value(DateTime.now())),
    );
  }
  return id;
}

/// The link text for a heading or paragraph link: "Title › Heading".
String partLinkText(String title, String part) {
  final clean = part.replaceAll(RegExp(r'\s+'), ' ').trim();
  final short = clean.length > 40
      ? '${clean.substring(0, 40).trimRight()}…'
      : clean;
  return '$title › $short';
}
