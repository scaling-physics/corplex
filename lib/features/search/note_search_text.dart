import '../ink/ink_model.dart';
import '../notes/note_content.dart';
import '../notes/note_table.dart';

/// The text a note is found by: its words (as [notePlainTextPreview]), plus
/// the handwriting recognised in its drawings and the cells of its tables.
/// Locked notes never come here (they are indexed by title only).
String noteSearchText(String content) {
  // Decode once: this runs for every changed note when the index builds.
  final document = decodeNoteContent(content);
  final base = previewOfDocument(document);
  final extra = <String>[];
  try {
    for (final op in document.toDelta().toList()) {
      final data = op.data;
      if (data is! Map) continue;
      final sketch = data['sketch'];
      if (sketch != null) {
        final raw = sketch is String ? sketch : null;
        final text = raw == null ? null : Sketch.decode(raw).text;
        if (text != null && text.trim().isNotEmpty) extra.add(text);
      }
      final table = data[tableEmbedType];
      if (table is String) {
        extra.add(NoteTable.decode(table).plainText);
      }
    }
  } catch (_) {
    // Search text is best effort; the note's own words still count.
  }
  if (extra.isEmpty) return base;
  return '$base ${extra.join(' ')}'.replaceAll(RegExp(r'\s+'), ' ').trim();
}
