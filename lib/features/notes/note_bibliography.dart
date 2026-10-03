import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../data/database.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import 'citation_embed.dart';

/// The heading of the reference list Corplex writes at the end of a note.
const referencesHeading = 'References';

/// Offset where a previously generated "References" section starts (a
/// level-2 heading with exactly that text), or null. Regenerating replaces
/// from here to the end of the note.
int? bibliographyStart(Delta delta) {
  var offset = 0;
  var lineStart = 0;
  final line = StringBuffer();
  int? found;
  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    if (data is! String) {
      offset += 1;
      line.write('￼');
      continue;
    }
    for (var i = 0; i < data.length; i++) {
      if (data[i] == '\n') {
        if (line.toString() == referencesHeading &&
            op.attributes?['header'] == 2) {
          found = lineStart;
        }
        line.clear();
        lineStart = offset + 1;
      } else {
        line.write(data[i]);
      }
      offset++;
    }
  }
  return found;
}

/// Writes (or rewrites) the note's reference list at its end, from the
/// `[@key]` citations in its text. Returns how many references it wrote;
/// 0 leaves the note untouched.
Future<int> insertBibliography(
  QuillController controller,
  AppDatabase db,
  CitationStyle style,
) async {
  final doc = controller.document;
  final start = bibliographyStart(doc.toDelta());
  // Citations show as chips in the editor; read their keys from the
  // document itself.
  final body = textWithCitations(doc.toDelta(), end: start);
  final papers = await papersForCitekeys(db, citedKeys(body));
  if (papers.isEmpty) return 0;

  final end = doc.length - 1; // before the final newline
  var at = start ?? end;
  if (start != null) controller.replaceText(start, end - start, '', null);
  // A blank line before the heading, so it doesn't sit against the last
  // paragraph (unless the note is empty there).
  if (at > 0) {
    final before = doc.toPlainText().substring(0, at);
    final gap = before.endsWith('\n\n')
        ? ''
        : before.endsWith('\n')
        ? '\n'
        : '\n\n';
    controller.replaceText(at, 0, gap, null);
    at += gap.length;
  }
  final refs = referenceList(papers, style);
  controller.replaceText(at, 0, '$referencesHeading\n${refs.join('\n')}', null);
  controller.formatText(at, referencesHeading.length, Attribute.h2);
  return refs.length;
}
