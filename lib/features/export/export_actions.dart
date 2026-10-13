import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../csl/csl_format.dart';
import '../csl/csl_rich.dart';
import '../csl/style_picker.dart';
import '../library/citation_formatter.dart';
import '../library/citations.dart';
import '../projects/figures.dart';
import '../notes/note_content.dart';
import 'docx_export.dart';
import 'export_model.dart';
import 'markdown_export.dart';
import 'pdf_export.dart';

enum ExportFormat {
  markdown('Markdown', 'md', Icons.tag),
  word('Word document', 'docx', Icons.description_outlined),
  pdf('PDF', 'pdf', Icons.picture_as_pdf_outlined);

  const ExportFormat(this.label, this.extension, this.icon);

  final String label;
  final String extension;
  final IconData icon;
}

/// A safe file name from a title: letters, digits, spaces, dashes.
String exportFileName(String title, ExportFormat format) {
  final base = title
      .trim()
      .replaceAll(RegExp(r'[^\w\- ]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${base.isEmpty ? 'Corplex export' : base}.${format.extension}';
}

/// Renders [doc] into a file in [dir] and returns it.
Future<File> writeExport(
  ExportDoc doc,
  ExportFormat format,
  Directory dir, {
  FontLoader? loadFont,
}) async {
  dir.createSync(recursive: true);
  final file = File(p.join(dir.path, exportFileName(doc.title, format)));
  switch (format) {
    case ExportFormat.markdown:
      await file.writeAsString(exportToMarkdown(doc));
    case ExportFormat.word:
      await file.writeAsBytes(exportToDocx(doc));
    case ExportFormat.pdf:
      await file.writeAsBytes(await exportToPdf(doc, loadFont: loadFont));
  }
  return file;
}

/// Asks for a format and a reference style. Null if dismissed.
Future<({ExportFormat format, CitationStyle style})?> showExportSheet(
  BuildContext context,
) {
  return showModalBottomSheet<({ExportFormat format, CitationStyle style})>(
    context: context,
    builder: (_) => const _ExportSheet(),
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  CitationStyle _style = CitationStyle.apa;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Citations and references'),
            subtitle: Text(_style.label),
            trailing: const Icon(Icons.expand_more),
            onTap: () async {
              final picked = await pickCitationStyle(context);
              if (picked != null) setState(() => _style = picked);
            },
          ),
          for (final f in ExportFormat.values)
            ListTile(
              leading: Icon(f.icon),
              title: Text(f.label),
              onTap: () => Navigator.pop(context, (format: f, style: _style)),
            ),
        ],
      ),
    );
  }
}

/// Renders and shares [doc], with a short message if it fails.
Future<void> shareExport(
  BuildContext context,
  ExportDoc doc,
  ExportFormat format,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'exports'),
    );
    final file = await writeExport(doc, format, dir);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: doc.title.isEmpty ? null : doc.title,
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Couldn\'t create that file.')),
    );
  }
}

/// Convenience used by the screens: ask, build, share.
Future<void> exportNotes(
  BuildContext context,
  AppDatabase db,
  List<ExportNote> notes, {
  required String title,
  FigureIndex? figures,
  List<ExportBlock> extraFrontMatter = const [],
}) async {
  final choice = await showExportSheet(context);
  if (choice == null || !context.mounted) return;
  final doc = await buildStyledExportDoc(
    db,
    notes,
    title: title,
    style: choice.style,
    figures: figures,
    extraFrontMatter: extraFrontMatter,
  );
  if (!context.mounted) return;
  await shareExport(context, doc, choice.format);
}

/// Like [buildExportDoc], but a CSL style (bundled or imported) formats the
/// in-text citations and the reference list with its real rules: numbered
/// styles number in order of first citation, author-date styles get
/// 2017a/2017b where needed. Other styles go through [buildExportDoc].
Future<ExportDoc> buildStyledExportDoc(
  AppDatabase db,
  List<ExportNote> notes, {
  required String title,
  required CitationStyle style,
  FigureIndex? figures,
  List<ExportBlock> extraFrontMatter = const [],
}) async {
  Future<ExportDoc> plain(List<ExportNote> n, CitationStyle st) =>
      buildExportDoc(
        db,
        n,
        title: title,
        style: st,
        figures: figures,
        extraFrontMatter: extraFrontMatter,
      );
  if (!style.isCsl) return plain(notes, style);
  // Read each note's text pieces once, in order.
  final deltas = [
    for (final n in notes)
      [
        for (final op in decodeNoteContent(n.content).toDelta().toList())
          op.toJson(),
      ],
  ];
  String? textOf(Map op) =>
      op['insert'] is String ? op['insert'] as String : null;
  final pieces = <String>[];
  final keys = <String>[];
  for (final ops in deltas) {
    for (final op in ops) {
      final t = textOf(op);
      if (t == null) continue;
      pieces.add(t);
      for (final k in citedKeys(t)) {
        if (!keys.contains(k)) keys.add(k);
      }
    }
  }
  final papers = await papersForCitekeys(db, keys);
  final plan = await CslCitationPlan.build(pieces, {
    for (final p in papers) p.citekey!: p,
  }, style);
  if (plan == null) return plain(notes, style);
  final rewritten = <ExportNote>[];
  for (var i = 0; i < notes.length; i++) {
    for (final op in deltas[i]) {
      final t = textOf(op);
      if (t != null) op['insert'] = plan.replace(t);
    }
    rewritten.add(ExportNote(notes[i].title, jsonEncode(deltas[i])));
  }
  final doc = await buildExportDoc(
    db,
    rewritten,
    title: title,
    figures: figures,
    extraFrontMatter: extraFrontMatter,
  );
  if (plan.cited.isEmpty) return doc;
  final refs = await referenceEntries(plan.cited, style);
  return ExportDoc(title, [
    ...doc.blocks,
    const ExportBlock(BlockKind.heading2, [Run('References')]),
    for (final r in refs)
      ExportBlock(BlockKind.paragraph, [
        for (final span in r.spans)
          Run(
            span.vAlign == 1
                ? CslRich([span]).plainWithSuperscripts
                : span.text,
            italic: span.italic,
            bold: span.bold,
          ),
      ]),
  ]);
}
