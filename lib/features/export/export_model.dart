import 'package:flutter_quill/quill_delta.dart';

import '../../data/database.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import '../library/highlights.dart';
import '../audio/audio_link.dart';
import '../notes/note_content.dart';
import '../notes/math_markers.dart';
import '../notes/note_links.dart';

/// A note (or several) flattened to what every output format needs:
/// headings, paragraphs, lists, quotes and styled runs of text. The
/// renderers for Markdown, Word and PDF all read this, so citations and
/// the bibliography are resolved exactly once.
enum BlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  ordered,
  quote,

  /// A display equation: one run whose text is the LaTeX source.
  displayMath,
}

class Run {
  const Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.link,
    this.math = false,
  });

  /// The text, or the LaTeX source when [math] is set.
  final String text;

  /// An inline equation.
  final bool math;
  final bool bold;
  final bool italic;
  final bool strike;

  /// An external URL only; Corplex's own links mean nothing outside it.
  final String? link;
}

class ExportBlock {
  const ExportBlock(this.kind, this.runs, {this.ordinal = 0});

  final BlockKind kind;
  final List<Run> runs;

  /// 1-based position within a numbered list.
  final int ordinal;

  String get text => runs.map((r) => r.text).join();
}

class ExportDoc {
  const ExportDoc(this.title, this.blocks);

  final String title;
  final List<ExportBlock> blocks;
}

/// One note to export: its title and Quill content.
class ExportNote {
  const ExportNote(this.title, this.content);

  final String title;
  final String content;
}

const _references = 'References';

/// Builds the export of [notes] (one document; several notes become
/// chapters under their titles). `[@key]` citations become in-text
/// citations in [style] and a reference list is added at the end.
Future<ExportDoc> buildExportDoc(
  AppDatabase db,
  List<ExportNote> notes, {
  required String title,
  CitationStyle style = CitationStyle.apa,
}) async {
  final deltas = [
    for (final n in notes) decodeNoteContent(n.content).toDelta(),
  ];
  final keys = <String>[];
  for (final d in deltas) {
    for (final k in citedKeys(_plain(d))) {
      if (!keys.contains(k)) keys.add(k);
    }
  }
  final papers = await papersForCitekeys(db, keys);
  final resolver = CitationResolver({
    for (final p in papers) p.citekey!: p,
  }, style);

  final blocks = <ExportBlock>[];
  for (var i = 0; i < notes.length; i++) {
    final own = _blocks(deltas[i], resolver);
    if (notes.length > 1) {
      final heading = notes[i].title.trim().isEmpty
          ? 'Untitled'
          : notes[i].title.trim();
      blocks.add(ExportBlock(BlockKind.heading1, [Run(heading)]));
      blocks.addAll(_withoutReferences(own));
    } else {
      blocks.addAll(_withoutReferences(own));
    }
  }
  final cited = resolver.cited;
  if (cited.isNotEmpty) {
    blocks.add(const ExportBlock(BlockKind.heading2, [Run(_references)]));
    for (final ref in referenceList(cited, style)) {
      blocks.add(ExportBlock(BlockKind.paragraph, [Run(ref)]));
    }
  }
  return ExportDoc(title, blocks);
}

String _plain(Delta d) => [
  for (final op in d.toList())
    if (op.isInsert && op.data is String) op.data as String,
].join();

/// Drops a "References" section the reader generated in the note itself
/// (the export writes a fresh one).
List<ExportBlock> _withoutReferences(List<ExportBlock> blocks) {
  final at = blocks.indexWhere(
    (b) => b.kind == BlockKind.heading2 && b.text.trim() == _references,
  );
  return at < 0 ? blocks : blocks.sublist(0, at);
}

List<ExportBlock> _blocks(Delta delta, CitationResolver resolver) {
  final blocks = <ExportBlock>[];
  var runs = <Run>[];
  var ordinal = 0;

  for (final op in delta.toList()) {
    if (!op.isInsert) continue;
    final data = op.data;
    final attrs = op.attributes ?? const <String, dynamic>{};
    if (data is Map) {
      if (data[mathInlineType] case final String tex) {
        runs.add(Run(tex, math: true));
      } else if (data[mathBlockType] case final String tex) {
        if (runs.isNotEmpty) {
          blocks.add(ExportBlock(BlockKind.paragraph, runs));
          runs = [];
        }
        blocks.add(ExportBlock(BlockKind.displayMath, [Run(tex, math: true)]));
      } else {
        runs.add(Run(data.containsKey('sketch') ? '[Sketch]' : ''));
      }
      continue;
    }
    final parts = (data as String).split('\n');
    for (var i = 0; i < parts.length; i++) {
      final endsLine = i < parts.length - 1;
      // A line that is only `$$ … $$` is a display equation.
      final display =
          endsLine && runs.isEmpty && _kind(attrs) == BlockKind.paragraph
          ? displayMathOf(parts[i])
          : null;
      if (display != null) {
        blocks.add(
          ExportBlock(BlockKind.displayMath, [Run(display, math: true)]),
        );
        continue;
      }
      if (parts[i].isNotEmpty) runs.addAll(_runs(parts[i], attrs, resolver));
      if (endsLine) {
        // A newline: its attributes are the line's block style.
        final list = attrs['list'];
        ordinal = list == 'ordered' ? ordinal + 1 : 0;
        blocks.add(ExportBlock(_kind(attrs), runs, ordinal: ordinal));
        runs = [];
      }
    }
  }
  if (runs.isNotEmpty) blocks.add(ExportBlock(BlockKind.paragraph, runs));
  return blocks;
}

/// The runs of one line's worth of text: prose with inline `$…$` maths
/// pulled out (code spans keep their dollars).
List<Run> _runs(
  String text,
  Map<String, dynamic> attrs,
  CitationResolver resolver,
) {
  final spans = attrs.containsKey('code')
      ? const <MathSpan>[]
      : findInlineMath(text);
  if (spans.isEmpty) return [_run(text, attrs, resolver)];
  final out = <Run>[];
  var pos = 0;
  for (final m in spans) {
    if (m.start > pos) {
      out.add(_run(text.substring(pos, m.start), attrs, resolver));
    }
    out.add(Run(m.latex, math: true, bold: attrs['bold'] == true));
    pos = m.end;
  }
  if (pos < text.length) out.add(_run(text.substring(pos), attrs, resolver));
  return out;
}

Run _run(String text, Map<String, dynamic> attrs, CitationResolver resolver) {
  final link = attrs['link'] as String?;
  final internal =
      link != null &&
      (parseNoteLink(link) != null ||
          parsePaperPageLink(link) != null ||
          parseAudioTimestampLink(link) != null);
  return Run(
    resolver.replace(text),
    bold: attrs['bold'] == true,
    italic: attrs['italic'] == true,
    strike: attrs['strike'] == true,
    link: link != null && !internal ? link : null,
  );
}

BlockKind _kind(Map<String, dynamic> attrs) {
  return switch (attrs['header']) {
    1 => BlockKind.heading1,
    2 => BlockKind.heading2,
    3 => BlockKind.heading3,
    _ =>
      attrs['list'] == 'bullet'
          ? BlockKind.bullet
          : attrs['list'] == 'ordered'
          ? BlockKind.ordered
          : attrs['blockquote'] == true
          ? BlockKind.quote
          : BlockKind.paragraph,
  };
}
