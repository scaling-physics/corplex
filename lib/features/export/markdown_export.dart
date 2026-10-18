import 'export_model.dart';

/// Markdown for [doc]: the title as `#`, note headings shifted down one
/// level so they sit under it.
String exportToMarkdown(ExportDoc doc) {
  final out = StringBuffer();
  BlockKind? previous;
  final code = <String>[];
  void flushCode() {
    if (code.isEmpty) return;
    if (out.isNotEmpty) out.write('\n\n');
    out.write('```\n${code.join('\n')}\n```');
    code.clear();
    previous = BlockKind.code;
  }

  for (final b in doc.blocks) {
    if (b.kind == BlockKind.code) {
      code.add(b.text);
      continue;
    }
    flushCode();
    final text = b.runs.map(_inline).join();
    final line = switch (b.kind) {
      BlockKind.heading1 => '## $text',
      BlockKind.heading2 => '### $text',
      BlockKind.heading3 => '#### $text',
      BlockKind.bullet => '- $text',
      BlockKind.ordered => '${b.ordinal}. $text',
      BlockKind.quote => '> $text',
      BlockKind.paragraph || BlockKind.caption => text,
      BlockKind.displayMath => '\$\$\n${b.text}\n\$\$',
      BlockKind.code => text,
    };
    // Markdown paragraphs are separated by a blank line; list items stick
    // together. Empty lines in the note are just that blank line.
    if (text.isEmpty && b.kind == BlockKind.paragraph) {
      previous = null;
      continue;
    }
    final sameList =
        previous == b.kind &&
        (b.kind == BlockKind.bullet || b.kind == BlockKind.ordered);
    if (out.isNotEmpty) out.write(sameList ? '\n' : '\n\n');
    out.write(line);
    previous = b.kind;
  }
  flushCode();
  final body = out.toString().trim();
  final heading = doc.title.trim().isEmpty ? '' : '# ${doc.title.trim()}\n\n';
  return '$heading$body\n';
}

String _inline(Run r) {
  var out = r.text;
  if (out.isEmpty) return out;
  if (r.math) return '\$$out\$';
  if (r.bold) out = '**$out**';
  if (r.italic) out = '*$out*';
  if (r.strike) out = '~~$out~~';
  if (r.highlight != null) out = '==$out==';
  if (r.link != null) out = '[$out](${r.link})';
  return out;
}
