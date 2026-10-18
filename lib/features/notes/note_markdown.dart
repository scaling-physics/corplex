import '../audio/audio_link.dart';
import '../library/highlights.dart';
import '../projects/figures.dart';
import 'figure_markers.dart';
import 'math_markers.dart';
import 'note_content.dart';
import 'note_highlight.dart' show highlightHex;
import 'note_links.dart';

/// Converts a note to Markdown for sharing or export: headings, bold,
/// italic, strikethrough, lists, quotes and links. Corplex's own links
/// (other notes, paper pages, audio timestamps) only mean something inside
/// the app, so they're written as their plain text; sketches become a
/// "[Sketch]" placeholder. Figure and table captions become
/// "**Figure 2.** caption" and references "Figure 2", numbered within this
/// note alone (a project's chapter numbers need the other notes).
String noteToMarkdown({
  required String title,
  required String content,
  FigureIndex? figures,
}) {
  // The editor's form (figure chips) is turned back to markers first.
  final stored = figureEmbedsToText(content);
  final index =
      figures ??
      buildFigureIndex([FigureNote(noteId: '', title: title, content: stored)]);
  final delta = decodeNoteContent(stored).toDelta();
  final lines = <String>[];
  // Raw (unformatted) text of each line that is a code-block line, else null.
  final codeOf = <String?>[];
  var raw = StringBuffer();
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
        raw.write(data.containsKey('sketch') ? '[Sketch]' : '');
      }
      continue;
    }
    final text = data as String;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (line.isEmpty && part.isNotEmpty) {
        final m = findFigureMarkers(part).firstOrNull;
        if (m != null && m.isDefinition && m.start == 0) {
          line.write('**${index.nameOf(m.kind, m.label)}.**');
          part = part.substring(m.end);
        }
      }
      part = index.resolve(part);
      if (part.isNotEmpty) {
        line.write(_inline(part, attrs));
        raw.write(part);
      }
      if (i < parts.length - 1) {
        // A newline: its attributes are the line's block style.
        final list = attrs['list'];
        ordinal = list == 'ordered' ? ordinal + 1 : 0;
        final isCode =
            attrs['code-block'] != null && attrs['code-block'] != false;
        lines.add(_block(line.toString(), attrs, ordinal));
        codeOf.add(isCode ? raw.toString() : null);
        line = StringBuffer();
        raw = StringBuffer();
      }
    }
  }
  if (line.isNotEmpty) {
    lines.add(line.toString());
    codeOf.add(null);
  }

  // Consecutive code-block lines share one fence.
  final fenced = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (codeOf[i] == null) {
      fenced.add(lines[i]);
      continue;
    }
    final open = i == 0 || codeOf[i - 1] == null;
    final close = i == lines.length - 1 || codeOf[i + 1] == null;
    fenced.add('${open ? '```\n' : ''}${codeOf[i]}${close ? '\n```' : ''}');
  }

  final body = fenced.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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
  if (highlightHex(attrs['background']) != null) out = '==$out==';
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
