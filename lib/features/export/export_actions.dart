import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../library/citation_formatter.dart';
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
            trailing: DropdownButton<CitationStyle>(
              value: _style,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in CitationStyle.values.where(
                  (s) => s != CitationStyle.bibtex,
                ))
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (s) => setState(() => _style = s ?? _style),
            ),
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
}) async {
  final choice = await showExportSheet(context);
  if (choice == null || !context.mounted) return;
  final doc = await buildExportDoc(
    db,
    notes,
    title: title,
    style: choice.style,
  );
  if (!context.mounted) return;
  await shareExport(context, doc, choice.format);
}
