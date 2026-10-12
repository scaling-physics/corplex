import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../library/citation_formatter.dart';
import 'csl_registry.dart';
import 'csl_style.dart';

/// Asks which reference style to use: every bundled CSL style, the
/// reader's own and "Add a style…" (imports a `.csl` file). The chosen
/// style is loaded before it is returned. Null if dismissed.
Future<CitationStyle?> pickCitationStyle(
  BuildContext context, {
  bool includeBibtex = false,
  String title = 'Reference style',
}) async {
  await CslRegistry.loadCustom();
  if (!context.mounted) return null;
  final picked = await showDialog<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final s in CitationStyle.all)
          if (includeBibtex || s != CitationStyle.bibtex)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s.label),
            ),
        const Divider(),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'add'),
          child: const Text('Add a style…'),
        ),
      ],
    ),
  );
  if (picked is CitationStyle) {
    await picked.ensureLoaded();
    return picked;
  }
  if (picked == 'add' && context.mounted) {
    return importStyleFromFile(context);
  }
  return null;
}

/// Lets the reader choose a `.csl` file and imports it. Shows a calm
/// message if it can't be used. Returns the new style, or null.
Future<CitationStyle?> importStyleFromFile(BuildContext context) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csl', 'xml'],
  );
  final path = file?.path;
  if (path == null || !context.mounted) return null;
  try {
    final info = await CslRegistry.importFile(path);
    return CitationStyle.byName(info.name);
  } on CslFormatException catch (e) {
    if (context.mounted) await _notice(context, e.message);
  }
  return null;
}

Future<void> _notice(BuildContext context, String message) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('That style can\'t be used'),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  ),
);
