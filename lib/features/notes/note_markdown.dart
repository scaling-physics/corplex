import '../audio/audio_link.dart';
import '../library/highlights.dart';
import 'math_markers.dart';
import 'note_content.dart';
import 'note_links.dart';

/// Converts a note to Markdown for sharing or export: headings, bold,
/// italic, strikethrough, lists, quotes and links. Corplex's own links
/// (other notes, paper pages, audio timestamps) only mean something inside
/// the app, so they're written as their plain text; sketches become a
/// "[Sketch]" placeholder.
String noteToMarkdown({required String title, required String content}) {
  final delta = decodeNoteContent(content).toDelta();
  final lines = <String>[];
  var line = StringBuffer();
  var ordinal = 0;

  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    final attrs = op.attributes ?? const <String, dynamic>{};

    if (data is Map) {
      if (data[mathInlineType] case final String tex) {
        line.write(inlineMathMarker(tex));
      } else if (data[mathBlockType] case final String tex) {
        line.write(displayMathMarker(tex));
      } else {
        line.write(data.containsKey('sketch') ? '[Sketch]' : '');
      }
      continue;
    }
    final text = data as String;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) line.write(_inline(parts[i], attrs));
      if (i < parts.length - 1) {
        // A newline: its attributes are the line's block style.
        final list = attrs['list'];
        ordinal = list == 'ordered' ? ordinal + 1 : 0;
        lines.add(_block(line.toString(), attrs, ordinal));
        line = StringBuffer();
      }
    }
  }
  if (line.isNotEmpty) lines.add(line.toString());

  final body = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  final heading = title.trim().isEmpty ? '' : '# ${title.trim()}\n\n';
  return '$heading$body\n';
}

String _inline(String text, Map<String, dynamic> attrs) {
  var out = text;
  final link = attrs['link'] as String?;
  final internal =
      link != null &&
      (parseNoteLink(link) != null ||
          parsePaperPageLink(link) != null ||
          parseAudioTimestampLink(link) != null);
  if (attrs['bold'] == true) out = '**$out**';
  if (attrs['italic'] == true) out = '*$out*';
  if (attrs['strike'] == true) out = '~~$out~~';
  if (link != null && !internal) out = '[$out]($link)';
  return out;
}

String _block(String text, Map<String, dynamic> attrs, int ordinal) {
  if (attrs['header'] case final int level) return '${'#' * (level + 1)} $text';
  if (attrs['list'] == 'bullet') return '- $text';
  if (attrs['list'] == 'ordered') return '$ordinal. $text';
  if (attrs['blockquote'] == true) return '> $text';
  return text;
}
