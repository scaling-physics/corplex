import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../platform/share_origin.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../home/adaptive.dart';
import 'bibtex.dart';
import 'reference_import.dart';
import 'metadata_lookup.dart';
import 'retraction.dart';
import '../ocr/ocr_service.dart';
import '../ocr/pdf_pages.dart';
import 'paper_detail_screen.dart';

void _say(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

void _openPaper(BuildContext context, String id) {
  // Beside the list on a tablet, as a page on a phone.
  if (hasDetailPane(context)) {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(selectedPaperProvider.notifier).state = id;
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PaperDetailScreen(paperId: id)));
}

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
          hintText: '10.1038/nature14539, arXiv:1706.03762 or PMID: 9500320',
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
    _say(context, 'That doesn\'t look like a DOI, arXiv or PubMed ID.');
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
    final result = await addPaperFromMetadata(db, meta, id: const Uuid().v4());
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
  final origin = shareOrigin(context);
  final papers = await db.select(db.papers).get();
  if (!context.mounted) return;
  if (papers.isEmpty) {
    _say(context, 'Your library is empty.');
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      text: exportBibtex(papers),
      subject: 'Corplex library.bib',
      sharePositionOrigin: origin,
    ),
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
  // Everything from the widget is taken now: the widget that started the
  // import may be gone by the time the lookup answers (the first-launch
  // welcome disappears as soon as the paper exists).
  final messenger = ScaffoldMessenger.maybeOf(context);
  final lookup = ref.read(metadataLookupProvider);
  final db = ref.read(databaseProvider);
  final ocr = ref.read(ocrServiceProvider);
  final open = ref.read(pdfPagesOpenerProvider);
  final retractions = ref.read(retractionServiceProvider);
  try {
    final start = await readPdfStart(
      pdfPath,
      open: open,
      ocr: ocr,
      paperId: paperId,
    );
    // A scan: the rest of its pages are recognised quietly in the background.
    if (start.scanned) ocr.enqueue(paperId);
    if (start.pageCount > 0) {
      // Known from the document we just opened; reading progress needs it.
      await (db.update(db.papers)..where((p) => p.id.equals(paperId))).write(
        PapersCompanion(pageCount: Value(start.pageCount)),
      );
    }
    final id = start.id;
    // No DOI or arXiv ID printed (many conference papers): search by the
    // title on the first page instead.
    final meta = id != null
        ? await lookup.lookup(id)
        : await lookup.searchByFirstPage(start.firstPage);
    if (meta == null) return;
    // Once, quietly: is the paper retracted? (Cached; shown on its screen.)
    if (meta.doi case final doi? when doi.isNotEmpty) {
      unawaited(checkNoticesInBackground(retractions, doi));
    }

    final duplicate = await findDuplicate(db, meta, excludePaperId: paperId);
    // The imported title is just the file name; replace it — but not a
    // title the reader has already typed in the meantime.
    final current = await (db.select(
      db.papers,
    )..where((p) => p.id.equals(paperId))).getSingleOrNull();
    if (current == null) return;
    final filled = await fillMissingMetadata(
      db,
      paperId,
      meta,
      replaceTitle: current.title == importedTitle,
    );
    if (filled && duplicate == null) {
      // Quietly say so: the title on screen just changed by itself.
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Found the details for “${meta.title}”')),
        );
    }
    if (duplicate != null && messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Looks like “${duplicate.title}” is already here.'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openPaper(messenger.context, duplicate.id),
            ),
          ),
        );
    }
  } catch (_) {
    // Offline, unreadable PDF, unknown id: the manual path still works.
  }
}

/// Reads the first pages of a PDF: a printed DOI or arXiv ID, if any, and
/// the first page's text (for a title search when there's no ID), and the
/// page count.
///
/// When the first pages have no text layer (a scan) and [ocr] and
/// [paperId] are given, those pages are recognised on-device first, so the
/// identifier and title search work on scans too; `scanned` is then true
/// and the caller queues the rest. Born-digital PDFs never touch OCR.
Future<({PaperIdentifier? id, String firstPage, int pageCount, bool scanned})>
readPdfStart(
  String path, {
  PdfPagesOpener open = PdfrxPages.open,
  OcrService? ocr,
  String? paperId,
}) async {
  final document = await open(path);
  try {
    final pageCount = document.pageCount;
    final texts = <String>[];
    var scanned = false;
    final canOcr = ocr != null && paperId != null;
    for (var i = 0; i < pageCount && i < 2; i++) {
      final text = await document.text(i);
      if (i == 0 && canOcr && pageLacksTextLayer(text)) {
        final second = pageCount > 1 ? await document.text(1) : '';
        if (pageLacksTextLayer(second)) {
          scanned = true;
          await ocr.markScanned(paperId, pageCount);
          for (var j = 0; j < pageCount && j < 2; j++) {
            final recognised = await ocr.recognizePage(document, paperId, j);
            texts.add(recognised?.text ?? '');
          }
        } else {
          texts
            ..add(text)
            ..add(second);
        }
        break;
      }
      texts.add(text);
      if (findIdentifierInText(text) != null) break;
    }
    final firstPage = texts.isEmpty ? '' : texts.first;
    PaperIdentifier? id;
    for (final text in texts) {
      id = findIdentifierInText(text);
      if (id != null) break;
    }
    return (
      id: id,
      firstPage: firstPage,
      pageCount: pageCount,
      scanned: scanned,
    );
  } finally {
    await document.dispose();
  }
}
