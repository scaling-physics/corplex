import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../data/database_provider.dart';
import 'bibtex.dart';
import 'reference_import.dart';
import 'metadata_lookup.dart';
import 'paper_detail_screen.dart';

void _say(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

void _openPaper(BuildContext context, String id) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: id)));

/// "Add by DOI or arXiv ID": asks for one (or a link), looks up its
/// details, and adds the paper unless it's already in the library.
Future<void> addPaperByIdentifier(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final input = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add by DOI or arXiv ID'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '10.1038/nature14539 or arXiv:1706.03762',
        ),
        keyboardType: TextInputType.url,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (input == null || input.trim().isEmpty || !context.mounted) return;

  final id = parseIdentifier(input);
  if (id == null) {
    _say(context, 'That doesn\'t look like a DOI or arXiv ID.');
    return;
  }
  await addPaperFromIdentifier(context, ref, id);
}

/// Looks [id] up and adds the paper (unless it's already in the library),
/// opening it when new. Says what happened either way.
Future<void> addPaperFromIdentifier(
  BuildContext context,
  WidgetRef ref,
  PaperIdentifier id,
) async {
  _say(context, 'Looking it up…');
  final db = ref.read(databaseProvider);
  try {
    final meta = await ref.read(metadataLookupProvider).lookup(id);
    if (!context.mounted) return;
    if (meta == null) {
      _say(context, 'No paper found for ${id.value}.');
      return;
    }
    final result = await addPaperFromMetadata(
      db,
      meta,
      id: const Uuid().v4(),
    );
    if (!context.mounted) return;
    if (result.existing case final existing?) {
      _say(
        context,
        'Already in your library.',
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => _openPaper(context, existing.id),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _openPaper(context, result.id!);
  } on LookupFailed {
    if (context.mounted) {
      _say(context, 'Couldn\'t reach the lookup service. Try again online.');
    }
  }
}

/// Imports every entry of a BibTeX, RIS or CSL JSON file (what Zotero,
/// Mendeley and EndNote export), skipping papers already in the library,
/// and reports what happened.
Future<void> importBibtexFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['bib', 'bibtex', 'ris', 'json', 'txt'],
  );
  if (picked?.path == null || !context.mounted) return;

  final text = await File(picked!.path!).readAsString();
  if (!context.mounted) return;
  final entries = parseReferences(text);
  if (entries.isEmpty) {
    _say(context, 'No references found in that file.');
    return;
  }
  final db = ref.read(databaseProvider);
  var added = 0;
  var skipped = 0;
  for (final entry in entries) {
    final result = await addPaperFromMetadata(db, entry, id: const Uuid().v4());
    result.id == null ? skipped++ : added++;
  }
  if (!context.mounted) return;
  _say(
    context,
    [
      'Added $added paper${added == 1 ? '' : 's'}',
      if (skipped > 0) '$skipped already in your library',
    ].join(' · '),
  );
}

/// Shares the whole library as one BibTeX file's worth of text.
Future<void> exportLibraryBibtex(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final papers = await db.select(db.papers).get();
  if (!context.mounted) return;
  if (papers.isEmpty) {
    _say(context, 'Your library is empty.');
    return;
  }
  await SharePlus.instance.share(
    ShareParams(text: exportBibtex(papers), subject: 'Corplex library.bib'),
  );
}

/// After a PDF is imported: read its identifier from the text, look up the
/// real details and fill in what's missing — quietly, and only online.
/// Never throws; a paper is just as usable without it.
Future<void> enrichImportedPaper(
  WidgetRef ref,
  BuildContext context,
  String paperId,
  String pdfPath, {
  required String importedTitle,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final id = await identifierFromPdf(pdfPath);
    if (id == null) return;
    final meta = await ref.read(metadataLookupProvider).lookup(id);
    if (meta == null) return;

    final db = ref.read(databaseProvider);
    final duplicate = await findDuplicate(db, meta, excludePaperId: paperId);
    // The imported title is just the file name; replace it — but not a
    // title the reader has already typed in the meantime.
    final current = await (db.select(
      db.papers,
    )..where((p) => p.id.equals(paperId))).getSingleOrNull();
    if (current == null) return;
    await fillMissingMetadata(
      db,
      paperId,
      meta,
      replaceTitle: current.title == importedTitle,
    );
    if (duplicate != null && context.mounted) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Looks like “${duplicate.title}” is already here.'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openPaper(context, duplicate.id),
            ),
          ),
        );
    }
  } catch (_) {
    // Offline, unreadable PDF, unknown id: the manual path still works.
  }
}

/// Reads the first pages of a PDF looking for a printed DOI or arXiv ID.
Future<PaperIdentifier?> identifierFromPdf(String path) async {
  final document = await PdfDocument.openFile(path);
  try {
    for (final page in document.pages.take(2)) {
      final text = await page.loadStructuredText();
      final id = findIdentifierInText(text.fullText);
      if (id != null) return id;
    }
    return null;
  } finally {
    await document.dispose();
  }
}
