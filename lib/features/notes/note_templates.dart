import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';

/// Headings of the literature-note template, in order.
const literatureNoteSections = ['Summary', 'Method', 'Findings', 'Critique'];

/// Writes the literature-note skeleton (a heading and an empty line per
/// section) at [index], and leaves the cursor under the first heading.
/// Returns the offset where the cursor was placed.
int insertLiteratureTemplate(QuillController controller, int index) {
  final doc = controller.document;
  var at = index;
  // Start on a fresh line.
  if (at > 0 && doc.toPlainText()[at - 1] != '\n') {
    controller.replaceText(at, 0, '\n', null);
    at++;
  }
  final start = at;
  int? cursor;
  for (final section in literatureNoteSections) {
    controller.replaceText(at, 0, '$section\n\n', null);
    controller.formatText(at, section.length, Attribute.h2);
    at += section.length + 2;
    cursor ??= start + section.length + 1;
  }
  controller.updateSelection(
    TextSelection.collapsed(offset: cursor!),
    ChangeSource.local,
  );
  return cursor;
}
