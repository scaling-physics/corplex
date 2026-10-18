import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';

import '../lock/note_crypto.dart' show isLockedContent;

/// Note content is stored as Quill Delta JSON. This decodes it back into a
/// [Document], falling back to treating the stored string as plain text for
/// notes created before rich text existed (or if the JSON is malformed).
///
/// A *locked* body (an encrypted envelope) is never text: it decodes to an
/// empty document, so no preview, count or export can ever show ciphertext
/// as if it were the note. Decrypt first (`NoteLockService.decryptBody`).
Document decodeNoteContent(String content) {
  if (content.isEmpty || isLockedContent(content)) return Document();
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
/// Figure/table markers read as words: a caption's `{#fig:x}` is dropped,
/// a reference `{@fig:x}` reads "Figure" (numbers need the project).
String notePlainTextPreview(String content) {
  if (content.isEmpty) return '';
  final cached = _previews.remove(content);
  if (cached != null) {
    _previews[content] = cached; // most recently used goes last
    return cached;
  }
  final preview = previewOfDocument(decodeNoteContent(content));
  _remember(content, preview);
  return preview;
}

/// [notePlainTextPreview] for a document already decoded.
String previewOfDocument(Document document) => document
    .toPlainText()
    .replaceAll('\uFFFC', '')
    .replaceAll(_captionMarker, '')
    .replaceAllMapped(
      _referenceMarker,
      (m) => m[1] == 'fig' ? 'Figure' : 'Table',
    )
    .replaceAll(_whitespace, ' ')
    .trim();

final _captionMarker = RegExp(r'\{#(?:fig|tbl):[A-Za-z0-9_-]+\}');
final _referenceMarker = RegExp(r'\{@(fig|tbl):[A-Za-z0-9_-]+\}');
final _whitespace = RegExp(r'\s+');

// List rows rebuild on every scroll, rebuild and sync; decoding a note's
// Quill JSON for its one-line subtitle each time is what made a 3,000-note
// list stutter. Keyed by the body itself (strings compare by value, and the
// key shares the instance the note row already holds), least recently used
// out first, bounded by count and by total characters retained.
final _previews = <String, String>{};
var _previewChars = 0;
const _previewEntries = 600;
const _previewCharBudget = 4000000;

void _remember(String content, String preview) {
  _previews[content] = preview;
  _previewChars += content.length;
  while (_previews.length > _previewEntries ||
      _previewChars > _previewCharBudget) {
    final oldest = _previews.keys.first;
    _previews.remove(oldest);
    _previewChars -= oldest.length;
  }
}

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
