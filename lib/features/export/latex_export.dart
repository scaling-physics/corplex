import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../data/database.dart';
import '../ink/sketch_render.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import '../notes/figure_markers.dart';
import '../notes/note_table.dart';
import 'export_model.dart';

/// A LaTeX project: `main.tex`, `references.bib` and the figure files.
class LatexProject {
  const LatexProject(this.main, this.bib, this.figures);

  final String main;
  final String bib;

  /// Path inside the project (`figures/sketch-1.png`) to PNG bytes.
  final Map<String, Uint8List> figures;
}

/// [buildLatexProject] zipped, with every drawing rendered to a PNG (needs
/// the Flutter engine). A drawing that won't render becomes "[Sketch]".
Future<List<int>> exportToLatexZip(ExportDoc doc) async {
  final images = <ExportBlock, Uint8List>{};
  for (final b in doc.blocks) {
    if (b.kind != BlockKind.image) continue;
    try {
      images[b] = await renderSketchPng(b.sketch!, width: 1600);
    } catch (_) {
      // Falls back to the placeholder.
    }
  }
  final project = buildLatexProject(doc, images: images);
  final archive = Archive()
    ..addFile(ArchiveFile.string('main.tex', project.main))
    ..addFile(ArchiveFile.string('references.bib', project.bib));
  project.figures.forEach((path, bytes) {
    archive.addFile(ArchiveFile.bytes(path, bytes));
  });
  return ZipEncoder().encode(archive);
}

/// Escapes LaTeX's special characters in running text (not for maths).
String latexEscape(String s) => s.replaceAllMapped(
  RegExp(r'[\\&%$#_{}~^]'),
  (m) => switch (m[0]!) {
    r'\' => r'\textbackslash{}',
    '~' => r'\textasciitilde{}',
    '^' => r'\textasciicircum{}',
    final c => '\\$c',
  },
);

/// The BibTeX entries of [papers], keyed by their citekeys.
String latexBibliography(List<Paper> papers) {
  final bib = StringBuffer();
  for (final pa in papers) {
    final key = pa.citekey;
    if (key == null || key.isEmpty) continue;
    final entry = formatCitation(pa, CitationStyle.bibtex);
    bib
      ..writeln(
        entry.replaceFirstMapped(
          RegExp(r'^(@\w+)\{[^,]*,'),
          (m) => '${m[1]}{$key,',
        ),
      )
      ..writeln();
  }
  return bib.toString();
}

/// Builds the LaTeX project for [doc].
///
/// natbib rather than biblatex: `\citep` / `\citealp` with optional notes
/// map one to one onto Corplex's `[@key, p. 42]`, and plain BibTeX needs no
/// backend setting in Overleaf (biblatex defaults to biber and breaks when
/// the compiler is switched). A project export (chapters) uses `report` and
/// `\chapter`; a single note uses `article`.
///
/// [images] holds the PNG for each drawing; one without becomes "[Sketch]".
LatexProject buildLatexProject(
  ExportDoc doc, {
  Map<ExportBlock, Uint8List> images = const {},
}) {
  var blocks = doc.blocks.skip(doc.figureListLength).toList();
  // The generated "References" section gives way to \bibliography.
  final cited = doc.papers.where((p) => p.citekey != null).toList();
  if (cited.isNotEmpty) {
    final at = blocks.lastIndexWhere(
      (b) => b.kind == BlockKind.heading2 && b.text.trim() == 'References',
    );
    if (at >= 0) blocks = blocks.sublist(0, at);
  }
  final report = blocks.any((b) => b.chapterTitle);
  final hasFigures = doc.figureListLength > 0;
  final style = doc.citationStyle;
  final numeric = style != null && (style.numeric || style.name == 'ieee');
  final bst = switch (style?.name) {
    'apa' => 'apalike',
    'ieee' => 'IEEEtran',
    _ when numeric => 'unsrtnat',
    _ => 'plainnat',
  };

  final figures = <String, Uint8List>{};
  var photoCount = 0;
  final body = StringBuffer();
  String? env;
  void close() {
    if (env != null) body.writeln('\\end{$env}');
    env = null;
  }

  void open(String name) {
    if (env == name) return;
    close();
    body.writeln('\\begin{$name}');
    env = name;
  }

  int next(int i) {
    var j = i + 1;
    while (j < blocks.length &&
        blocks[j].kind == BlockKind.paragraph &&
        blocks[j].runs.every((r) => r.text.isEmpty)) {
      j++;
    }
    return j;
  }

  String figureFile(ExportBlock b) {
    final png = images[b]!;
    final path = 'figures/sketch-${figures.length + 1}.png';
    figures[path] = png;
    return path;
  }

  String image(ExportBlock b) {
    final path = figureFile(b);
    final alt = (b.sketch!.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${alt.isEmpty ? '' : '% Handwriting: $alt\n'}'
        '\\includegraphics[width=\\linewidth,height=0.8\\textheight,'
        'keepaspectratio]{$path}';
  }

  String caption(ExportBlock c) =>
      '\\caption{${c.runs.skip(1).map(_run).join().trim()}}\n'
      '\\label{${c.figure!.kind.tag}:${c.figure!.label}}';

  String tabular(NoteTable t) {
    final cols = t.columns < 1 ? 1 : t.columns;
    String row(List<String> cells, bool head) =>
        '${cells.map((c) {
          final text = latexEscape(c.replaceAll(RegExp(r'\s*\n\s*'), ' '));
          return head && text.isNotEmpty ? '\\textbf{$text}' : text;
        }).join(' & ')} \\\\ \\hline';
    return '\\begin{tabularx}{\\linewidth}{|${'X|' * cols}}\n\\hline\n'
        '${[for (final (i, r) in t.rows.indexed) row(r, t.header && i == 0)].join('\n')}\n'
        '\\end{tabularx}';
  }

  String figureEnv(String inner, ExportBlock? cap, {required bool above}) {
    if (cap == null) return '\\begin{center}\n$inner\n\\end{center}';
    final kind = cap.figure!.kind == FigureKind.table ? 'table' : 'figure';
    return '\\begin{$kind}[htbp]\n\\centering\n'
        '${above ? '${caption(cap)}\n$inner' : '$inner\n${caption(cap)}'}\n'
        '\\end{$kind}';
  }

  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    switch (b.kind) {
      case BlockKind.heading1:
      case BlockKind.heading2:
      case BlockKind.heading3:
        close();
        // Inside a project a note's own H1 sits under its chapter.
        final level = switch (b.kind) {
          BlockKind.heading1 => b.chapterTitle ? 'chapter' : 'section',
          BlockKind.heading2 => 'subsection',
          _ => 'subsubsection',
        };
        body.writeln('\n\\$level{${b.runs.map(_run).join().trim()}}\n');
      case BlockKind.bullet:
        open('itemize');
        body.writeln('\\item ${b.runs.map(_run).join().trim()}');
      case BlockKind.ordered:
        if (b.ordinal == 1 && env == 'enumerate') close();
        open('enumerate');
        body.writeln('\\item ${b.runs.map(_run).join().trim()}');
      case BlockKind.quote:
        if (env == 'quote') body.writeln();
        open('quote');
        body.writeln(b.runs.map(_run).join().trim());
      case BlockKind.code:
        open('verbatim');
        // `\end{verbatim}` would end the block early.
        body.writeln(b.text.replaceAll(r'\end{verbatim}', r'\end {verbatim}'));
      case BlockKind.displayMath:
        close();
        body.writeln('\\[\n${b.text.trim()}\n\\]\n');
      case BlockKind.paragraph:
        if (b.runs.every((r) => r.text.isEmpty)) {
          if (env == null) body.writeln();
          continue;
        }
        close();
        body.writeln('${b.runs.map(_run).join().trim()}\n');
      case BlockKind.image:
        close();
        if (images[b] == null) {
          body.writeln('[Sketch]\n');
          break;
        }
        final j = next(i);
        final cap =
            j < blocks.length &&
                blocks[j].kind == BlockKind.caption &&
                blocks[j].figure?.kind == FigureKind.figure
            ? blocks[j]
            : null;
        body.writeln('${figureEnv(image(b), cap, above: false)}\n');
        if (cap != null) i = j;
      case BlockKind.photo:
        close();
        final photo = b.photo!;
        final path = 'figures/image-${photoCount + 1}.${photo.ext}';
        photoCount++;
        figures[path] = photo.bytes;
        final inc =
            '\\includegraphics[width=\\linewidth,height=0.7\\textheight,'
            'keepaspectratio]{$path}';
        body.writeln(
          photo.caption == null
              ? '\\begin{center}\n$inc\n\\end{center}\n'
              : '\\begin{figure}[htbp]\n\\centering\n$inc\n'
                    '\\caption{${latexEscape(photo.caption!)}}\n'
                    '\\end{figure}\n',
        );
      case BlockKind.table:
        close();
        final j = next(i);
        final cap =
            j < blocks.length &&
                blocks[j].kind == BlockKind.caption &&
                blocks[j].figure?.kind == FigureKind.table
            ? blocks[j]
            : null;
        body.writeln('${figureEnv(tabular(b.table!), cap, above: true)}\n');
        if (cap != null) i = j;
      case BlockKind.caption:
        close();
        final fig = b.figure;
        if (fig == null) {
          body.writeln('${b.runs.map(_run).join().trim()}\n');
          break;
        }
        final j = next(i);
        // A caption written above its drawing or table belongs to it.
        if (j < blocks.length) {
          final n = blocks[j];
          if (fig.kind == FigureKind.figure &&
              n.kind == BlockKind.image &&
              images[n] != null) {
            body.writeln('${figureEnv(image(n), b, above: false)}\n');
            i = j;
            break;
          }
          if (fig.kind == FigureKind.table && n.kind == BlockKind.table) {
            body.writeln('${figureEnv(tabular(n.table!), b, above: true)}\n');
            i = j;
            break;
          }
        }
        // Nothing to attach it to: keep the numbering and the label alive.
        final kind = fig.kind == FigureKind.table ? 'table' : 'figure';
        body.writeln('\\begin{$kind}[htbp]\n${caption(b)}\n\\end{$kind}\n');
    }
  }
  close();

  final title = doc.title.trim();
  final tex = StringBuffer()
    ..writeln('% Exported from Corplex.')
    ..writeln('\\documentclass[11pt]{${report ? 'report' : 'article'}}')
    ..writeln('\\usepackage[utf8]{inputenc}')
    ..writeln('\\usepackage[T1]{fontenc}')
    ..writeln('\\usepackage{amsmath,amssymb}')
    ..writeln('\\usepackage{graphicx}')
    ..writeln('\\usepackage{xcolor}')
    ..writeln('\\usepackage[normalem]{ulem}')
    ..writeln('\\usepackage{tabularx}')
    ..writeln('\\usepackage[${numeric ? 'numbers,' : ''}round]{natbib}')
    ..writeln('\\usepackage[hidelinks]{hyperref}')
    ..writeln('\\title{${latexEscape(title)}}')
    ..writeln('\\author{}')
    ..writeln('\\date{}')
    ..writeln()
    ..writeln('\\begin{document}');
  if (title.isNotEmpty) tex.writeln('\\maketitle');
  if (report) tex.writeln('\\tableofcontents');
  if (hasFigures) {
    if (blocks.any((b) => b.figure?.kind == FigureKind.figure)) {
      tex.writeln('\\listoffigures');
    }
    if (blocks.any((b) => b.figure?.kind == FigureKind.table)) {
      tex.writeln('\\listoftables');
    }
  }
  tex
    ..writeln()
    ..write(body.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim())
    ..writeln();
  if (cited.isNotEmpty) {
    tex
      ..writeln()
      ..writeln('\\bibliographystyle{$bst}')
      ..writeln('\\bibliography{references}');
  }
  tex.writeln('\\end{document}');
  return LatexProject(tex.toString(), latexBibliography(doc.papers), figures);
}

final _markers = RegExp(r'\[@[^\]\[]+\]|\{[@#](?:fig|tbl):[A-Za-z0-9_-]+\}');

/// One run as LaTeX: citation and figure markers become `\citep` / `\ref`,
/// the rest is escaped, then bold, italic, strike, highlight and link wrap
/// it. Maths is passed through untouched.
String _run(Run r) {
  if (r.math) return '\$${r.text}\$';
  final source = r.source ?? r.text;
  if (source.isEmpty) return '';
  final out = StringBuffer();
  var pos = 0;
  for (final m in _markers.allMatches(source)) {
    out.write(latexEscape(source.substring(pos, m.start)));
    pos = m.end;
    final text = m[0]!;
    if (text.startsWith('[')) {
      final items = parseCitationGroup(text);
      out.write(items.isEmpty ? latexEscape(text) : _cite(items));
    } else if (text.startsWith('{@')) {
      final fig = parseFigureMarker(text)!;
      out.write('${fig.kind.title}~\\ref{${fig.kind.tag}:${fig.label}}');
    }
    // A definition marker inside text carries no printed form.
  }
  out.write(latexEscape(source.substring(pos)));
  var s = out.toString();
  if (s.isEmpty) return s;
  if (r.bold) s = '\\textbf{$s}';
  if (r.italic) s = '\\textit{$s}';
  if (r.strike) s = '\\sout{$s}';
  if (r.highlight != null) s = '\\colorbox[HTML]{${r.highlight}}{$s}';
  if (r.link != null) {
    final url = r.link!.replaceAll('%', r'\%').replaceAll('#', r'\#');
    s = '\\href{$url}{$s}';
  }
  return s;
}

String _cite(List<CiteItem> items) {
  String? note(CiteItem i) {
    final d = i.display;
    if (d == null) return null;
    return latexEscape(d)
        .replaceFirstMapped(RegExp(r'^([A-Za-z]+\.) '), (m) => '${m[1]}~');
  }

  String one(CiteItem i, String cmd) {
    final n = note(i);
    return '\\$cmd${n == null ? '' : '[$n]'}{${i.key}}';
  }

  if (items.every((i) => !i.hasLocator)) {
    return '\\citep{${items.map((i) => i.key).join(',')}}';
  }
  if (items.length == 1) return one(items.single, 'citep');
  return '\\citetext{${items.map((i) => one(i, 'citealp')).join('; ')}}';
}
