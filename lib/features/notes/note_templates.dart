import 'package:flutter/painting.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/l10n.dart';

/// Headings of the literature-note template, in order (English; the
/// inserted headings follow the app language, see [insertLiteratureTemplate]).
const literatureNoteSections = ['Summary', 'Method', 'Findings', 'Critique'];

/// Writes the literature-note skeleton (a heading and an empty line per
/// section) at [index], and leaves the cursor under the first heading.
/// The headings are written in [l10n]'s language (English by default).
/// Returns the offset where the cursor was placed.
int insertLiteratureTemplate(
  QuillController controller,
  int index, {
  AppLocalizations? l10n,
}) {
  final sections = l10n == null
      ? literatureNoteSections
      : [
          l10n.notesTemplateSummary,
          l10n.notesTemplateMethod,
          l10n.notesTemplateFindings,
          l10n.notesTemplateCritique,
        ];
  final doc = controller.document;
  var at = index;
  // Start on a fresh line.
  if (at > 0 && doc.toPlainText()[at - 1] != '\n') {
    controller.replaceText(at, 0, '\n', null);
    at++;
  }
  final start = at;
  int? cursor;
  for (final section in sections) {
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
