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

/// Appends a quoted passage to [content]: the quote as a block quote, then
/// "— p. 12" linked to [pageLink] (so tapping it reopens the PDF there),
/// then the reader's [comment], if any. Returns the new content.
String appendQuote(
  String content, {
  required String quote,
  required int page,
  required String pageLink,
  String? comment,
}) {
  final doc = decodeNoteContent(content);
  // Every insert goes just before the document's final newline.
  int end() => doc.length - 1;

  if (doc.toPlainText().trim().isNotEmpty) doc.insert(end(), '\n');
  final quoteAt = end();
  doc.insert(quoteAt, '$quote\n');
  doc.format(quoteAt + quote.length, 1, Attribute.blockQuote);

  final label = 'p. $page';
  final refAt = end();
  doc.insert(refAt, '— $label');
  doc.format(refAt + 2, label.length, LinkAttribute(pageLink));

  if (comment != null && comment.trim().isNotEmpty) {
    doc.insert(end(), '\n${comment.trim()}');
  }
  // New lines split off a quoted line inherit its block quote style; only
  // the passage itself should be quoted.
  final afterQuote = quoteAt + quote.length + 1;
  doc.format(
    afterQuote,
    doc.length - afterQuote,
    Attribute.clone(Attribute.blockQuote, null),
  );
  return encodeNoteContent(doc);
}
