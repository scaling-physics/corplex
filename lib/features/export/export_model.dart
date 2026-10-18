import 'package:flutter_quill/quill_delta.dart';

import '../../data/database.dart';
import '../library/citation_formatter.dart';
import '../lock/note_crypto.dart' show isLockedContent;
import '../library/citations.dart';
import '../library/highlights.dart';
import '../audio/audio_link.dart';
import '../notes/note_content.dart';
import '../notes/note_highlight.dart' show highlightHex;
import '../notes/figure_markers.dart';
import '../notes/math_markers.dart';
import '../projects/figures.dart';
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

  /// A figure or table caption; its first run is the bold "Figure 3.2.".
  caption,

  /// A display equation: one run whose text is the LaTeX source.
  displayMath,

  /// One line of a monospaced (code) block; consecutive lines form a block.
  code,
}

class Run {
  const Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.link,
    this.math = false,
    this.highlight,
  });

  /// The highlight colour as `RRGGBB` (no `#`), or null.
  final String? highlight;

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

/// [notes] with any still-locked body emptied: a caller that couldn't
/// decrypt a note exports its title only, never the envelope.
List<ExportNote> withoutLockedBodies(List<ExportNote> notes) => [
  for (final n in notes)
    isLockedContent(n.content) ? ExportNote(n.title, '') : n,
];

const _references = 'References';

/// The "List of figures" / "List of tables" that open a project export
/// (nothing for a kind with no entries), then [extra] blocks (e.g. a list
/// of abbreviations). [text] resolves a caption's references and citations.
List<ExportBlock> exportFrontMatter(
  FigureIndex figures, {
  String Function(String caption)? text,
  List<ExportBlock> extra = const [],
}) {
  final out = <ExportBlock>[];
  for (final kind in FigureKind.values) {
    final entries = figures.ofKind(kind).toList();
    if (entries.isEmpty) continue;
    out.add(ExportBlock(BlockKind.heading2, [Run(kind.listTitle)]));
    for (final e in entries) {
      final caption = (text ?? figures.resolve)(e.caption).trim();
      out.add(
        ExportBlock(BlockKind.paragraph, [
          Run(caption.isEmpty ? e.name : '${e.name}  $caption'),
        ]),
      );
    }
  }
  return [...out, ...extra];
}

/// Builds the export of [notes] (one document; several notes become
/// chapters under their titles). `[@key]` citations become in-text
/// citations in [style] and a reference list is added at the end.
///
/// Figures and tables are numbered by [figures] when given (a single note
/// exported on its own passes the project's numbering, so it matches the
/// editor). Otherwise, with several notes (a project export, in chapter
/// order) a figure is "chapter.n" by the note's position; a lone note's is
/// "n". A multi-note export opens with the lists of figures and tables
/// followed by [extraFrontMatter].
Future<ExportDoc> buildExportDoc(
  AppDatabase db,
  List<ExportNote> notes, {
  required String title,
  CitationStyle style = CitationStyle.apa,
  FigureIndex? figures,
  List<ExportBlock> extraFrontMatter = const [],
}) async {
  notes = withoutLockedBodies(notes);
  final index =
      figures ??
      buildFigureIndex([
        for (final (i, n) in notes.indexed)
          FigureNote(
            noteId: '$i',
            title: n.title,
            content: n.content,
            chapter: notes.length > 1 ? '${i + 1}' : null,
          ),
      ]);
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
  if (notes.length > 1) {
    blocks.addAll(
      exportFrontMatter(
        index,
        text: (c) => resolver.replace(index.resolve(c)),
        extra: extraFrontMatter,
      ),
    );
  }
  for (var i = 0; i < notes.length; i++) {
    final own = _blocks(deltas[i], resolver, index);
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

List<ExportBlock> _blocks(
  Delta delta,
  CitationResolver resolver,
  FigureIndex figures,
) {
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
      if (parts[i].isNotEmpty) {
        runs.addAll(_runs(parts[i], attrs, resolver, figures));
      }
      if (endsLine) {
        // A newline: its attributes are the line's block style.
        final list = attrs['list'];
        ordinal = list == 'ordered' ? ordinal + 1 : 0;
        blocks.add(_line(_kind(attrs), runs, ordinal, figures));
        runs = [];
      }
    }
  }
  if (runs.isNotEmpty) {
    blocks.add(_line(BlockKind.paragraph, runs, 0, figures));
  }
  return blocks;
}

/// The runs of one line's worth of text: prose with inline `$…$` maths
/// pulled out (code spans keep their dollars).
List<Run> _runs(
  String text,
  Map<String, dynamic> attrs,
  CitationResolver resolver,
  FigureIndex figures,
) {
  final spans = attrs.containsKey('code')
      ? const <MathSpan>[]
      : findInlineMath(text);
  if (spans.isEmpty) return [_run(text, attrs, resolver, figures)];
  final out = <Run>[];
  var pos = 0;
  for (final m in spans) {
    if (m.start > pos) {
      out.add(_run(text.substring(pos, m.start), attrs, resolver, figures));
    }
    out.add(Run(m.latex, math: true, bold: attrs['bold'] == true));
    pos = m.end;
  }
  if (pos < text.length) {
    out.add(_run(text.substring(pos), attrs, resolver, figures));
  }
  return out;
}

/// A finished line: a paragraph that starts with a caption definition
/// becomes a [BlockKind.caption] opening with the bold "Figure 3.2.".
ExportBlock _line(
  BlockKind kind,
  List<Run> runs,
  int ordinal,
  FigureIndex figures,
) {
  if (kind == BlockKind.paragraph && runs.isNotEmpty) {
    final first = runs.first;
    final marker = findFigureMarkers(first.text).firstOrNull;
    if (!first.math &&
        marker != null &&
        marker.isDefinition &&
        marker.start == 0) {
      final rest = first.text.substring(marker.end);
      return ExportBlock(BlockKind.caption, [
        Run('${figures.nameOf(marker.kind, marker.label)}.', bold: true),
        if (rest.isNotEmpty)
          Run(
            rest,
            bold: first.bold,
            italic: first.italic,
            strike: first.strike,
            highlight: first.highlight,
            link: first.link,
          ),
        ...runs.skip(1),
      ]);
    }
  }
  return ExportBlock(kind, runs, ordinal: ordinal);
}

Run _run(
  String text,
  Map<String, dynamic> attrs,
  CitationResolver resolver,
  FigureIndex figures,
) {
  final link = attrs['link'] as String?;
  final internal =
      link != null &&
      (parseNoteLink(link) != null ||
          parsePaperPageLink(link) != null ||
          parseAudioTimestampLink(link) != null);
  return Run(
    resolver.replace(figures.resolve(text)),
    bold: attrs['bold'] == true,
    italic: attrs['italic'] == true,
    strike: attrs['strike'] == true,
    highlight: highlightHex(attrs['background']),
    link: link != null && !internal ? link : null,
  );
}

BlockKind _kind(Map<String, dynamic> attrs) {
  if (attrs['code-block'] != null && attrs['code-block'] != false) {
    return BlockKind.code;
  }
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
