import 'package:flutter_quill/flutter_quill.dart';

import 'block_ids.dart';
import 'callout_markers.dart';
import 'citation_embed.dart';
import 'date_markers.dart';
import 'figure_markers.dart';
import 'footnote_markers.dart';
import 'heading_fold.dart';
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
Document editorDocument(String stored) => decodeNoteContent(
  blockIdsToEmbeds(
    calloutsToEmbeds(
      figuresToEmbeds(
        citationsToEmbeds(
          dateMentionsToEmbeds(mathToEmbeds(footnotesToEmbeds(stored))),
        ),
      ),
    ),
  ),
);

/// The editor's document back to stored content (the inverse of
/// [editorDocument]), normalised the way the editor saves notes.
///
/// Collapsed sections (`heading_fold.dart`) exist only in the editor: they
/// are expanded first, so everything downstream sees the whole note.
String storedFromEditor(Document document) {
  final delta = document.toDelta();
  final whole = deltaHasFolds(delta)
      ? Document.fromDelta(unfoldDelta(delta))
      : document;
  // Footnote and callout embeds hold their text raw, so turning them back
  // first is the same as turning them back last (the design's order).
  return citationEmbedsToText(
    figureEmbedsToText(
      dateMentionEmbedsToText(
        mathEmbedsToText(
          footnoteEmbedsToText(
            calloutEmbedsToText(blockIdEmbedsToText(encodeNoteContent(whole))),
          ),
        ),
      ),
    ),
  );
}
