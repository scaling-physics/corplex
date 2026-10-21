import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';

/// Links between notes are ordinary Quill links, `corplex://note/<id>`, so
/// they survive sync, copy/paste and export like any other link. Their
/// text is the target's title at the time of linking.
///
/// A link to part of a note adds a fragment: `#heading=<text>` (the
/// heading's text, URI-encoded, matched case-insensitively when opened) or
/// `#block=<id>` (a paragraph carrying the block marker ` ^<id>`, see
/// [blockIdPattern]). Anything matching `corplex://note/<id>` — backlinks,
/// the Map — sees these as links to the note without knowing about parts.
String noteLink(String noteId, {String? heading, String? block}) {
  assert(heading == null || block == null);
  final base = 'corplex://note/$noteId';
  if (heading != null) return '$base#heading=${Uri.encodeComponent(heading)}';
  if (block != null) return '$base#block=$block';
  return base;
}

/// Where a note link points: the note, and optionally one heading or block.
class NoteLinkTarget {
  const NoteLinkTarget(this.noteId, {this.heading, this.block});

  final String noteId;
  final String? heading;
  final String? block;

  @override
  bool operator ==(Object other) =>
      other is NoteLinkTarget &&
      other.noteId == noteId &&
      other.heading == heading &&
      other.block == block;

  @override
  int get hashCode => Object.hash(noteId, heading, block);

  @override
  String toString() => noteLink(noteId, heading: heading, block: block);
}

NoteLinkTarget? parseNoteLinkTarget(String link) {
  final id = parseNoteLink(link);
  if (id == null) return null;
  final fragment = Uri.tryParse(link)?.fragment ?? '';
  String? value(String key) => fragment.startsWith('$key=')
      ? Uri.decodeComponent(fragment.substring(key.length + 1))
      : null;
  final heading = value('heading');
  final block = value('block');
  return NoteLinkTarget(
    id,
    heading: heading != null && heading.isNotEmpty ? heading : null,
    block: block != null && blockIdChars.hasMatch(block) ? block : null,
  );
}

/// A block id is Obsidian's: letters, digits and dashes.
final blockIdChars = RegExp(r'^[A-Za-z0-9-]+$');

/// The block marker as stored: a paragraph's text ending in ` ^<id>`
/// (Obsidian's syntax, so vault export and import keep it as is). Match it
/// against one line's text, without its newline.
final blockIdPattern = RegExp(r' \^([A-Za-z0-9-]+)$');

/// A fresh block id: six lowercase letters and digits, like Obsidian's.
String newBlockId([Random? random]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Another note shown inside a note (`![[Note]]` in Obsidian) is a block
/// embed of this type on its own line, stored in the Delta like sketches
/// and tables. Its data is [noteEmbedData]: JSON holding the note link
/// (with an optional heading/block fragment), so backlinks and the Map
/// find it by the same `corplex://note/<id>` text.
const noteEmbedType = 'noteembed';

String noteEmbedData(String link) => jsonEncode({'link': link});

/// The link inside a [noteEmbedType] embed's data, or null if malformed.
String? noteEmbedLink(String data) {
  try {
    final json = jsonDecode(data);
    final link = json is Map ? json['link'] : null;
    return link is String && parseNoteLink(link) != null ? link : null;
  } on FormatException {
    return null;
  }
}

String? parseNoteLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'corplex' ||
      uri.host != 'note' ||
      uri.pathSegments.length != 1) {
    return null;
  }
  return uri.pathSegments.single;
}

/// Notes that link to [noteId] — found by the link text itself in their
/// content, so there's no separate index to keep in sync.
final backlinksProvider = StreamProvider.autoDispose.family<List<Note>, String>(
  (ref, noteId) {
    final db = ref.watch(databaseProvider);
    return (db.select(db.notes)
          ..where(
            (n) =>
                n.content.like('%${noteLink(noteId)}%') &
                n.id.equals(noteId).not(),
          )
          ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
        .watch();
  },
);
