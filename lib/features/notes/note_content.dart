import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

/// Note content is stored as Quill Delta JSON. This decodes it back into a
/// [Document], falling back to treating the stored string as plain text for
/// notes created before rich text existed (or if the JSON is malformed).
Document decodeNoteContent(String content) {
  if (content.isEmpty) return Document();
  try {
    return Document.fromJson(jsonDecode(content) as List);
  } catch (_) {
    return Document()..insert(0, content);
  }
}

String encodeNoteContent(Document document) =>
    jsonEncode(document.toDelta().toJson());

/// A single-line plain-text preview for list rows, without loading a full
/// Quill controller just to render a subtitle.
/// Embeds (sketches) have no text, so they're dropped rather than shown as
/// the object-replacement character.
String notePlainTextPreview(String content) =>
    decodeNoteContent(content)
        .toPlainText()
        .replaceAll('\uFFFC', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
