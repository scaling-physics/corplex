import 'package:flutter_quill/flutter_quill.dart';

import 'citation_embed.dart';
import 'figure_markers.dart';
import 'math_markers.dart';
import 'note_content.dart';

/// The one crossing point between a note as *stored* (plain-text markers:
/// `[@key]` citations, `$…$` maths, `{#fig:x}` / `{@fig:x}` figure captions
/// and references, …) and the document the *editor* shows (each marker an
/// embed, one character long).
///
/// Anything that measures offsets for the editor (to-dos, selections to
/// open a note at) must build the document with [editorDocument], so a
/// marker added here later is counted the same way everywhere.
Document editorDocument(String stored) =>
    decodeNoteContent(figuresToEmbeds(citationsToEmbeds(mathToEmbeds(stored))));

/// The editor's document back to stored content (the inverse of
/// [editorDocument]), normalised the way the editor saves notes.
String storedFromEditor(Document document) => citationEmbedsToText(
  figureEmbedsToText(mathEmbedsToText(encodeNoteContent(document))),
);
