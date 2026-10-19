import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/local_files.dart';
import '../../l10n/l10n.dart';
import '../library/citations.dart';
import '../library/highlights.dart';
import '../library/metadata_lookup.dart';
import '../lock/note_crypto.dart';
import '../notes/note_content.dart';
import '../projects/projects_providers.dart';
import 'zotero_client.dart';
import 'zotero_mapping.dart';

/// Page sizes in PDF points for the PDF at a path, or null when they can't
/// be read. A seam: pdfrx doesn't run under `flutter test`.
typedef PageSizeReader = Future<List<Size>?> Function(String pdfPath);

Future<List<Size>?> readPageSizesWithPdfrx(String path) async {
  PdfDocument? doc;
  try {
    doc = await PdfDocument.openFile(path);
    return [for (final p in doc.pages) Size(p.width, p.height)];
  } catch (_) {
    return null;
  } finally {
    await doc?.dispose();
  }
}

typedef PdfSaver = Future<String> Function(Uint8List bytes, String fileName);

Future<String> savePdfToAppStorage(Uint8List bytes, String fileName) =>
    saveBytesToAppStorage(bytes, 'papers', fileName);

/// A Zotero collection, with the nesting flattened into [path].
class ZoteroCollection {
  const ZoteroCollection({
    required this.key,
    required this.name,
    required this.parent,
    required this.itemCount,
    required this.path,
    required this.depth,
  });

  final String key;
  final String name;
  final String? parent;
  final int itemCount;

  /// "Parent / Child": the project name this collection becomes.
  final String path;
  final int depth;
}

/// Collections in tree order (parents before their children, siblings by
/// name), with their flattened names.
List<ZoteroCollection> parseCollections(List<Map<String, dynamic>> raw) {
  final byParent = <String?, List<Map<String, dynamic>>>{};
  for (final c in raw) {
    final d = zoteroData(c);
    final parent = d['parentCollection'];
    byParent.putIfAbsent(parent is String ? parent : null, () => []).add(c);
  }
  final out = <ZoteroCollection>[];
  void walk(String? parent, String prefix, int depth) {
    final kids = [...?byParent[parent]]
      ..sort(
        (a, b) => (zoteroData(a)['name'] as String? ?? '')
            .toLowerCase()
            .compareTo((zoteroData(b)['name'] as String? ?? '').toLowerCase()),
      );
    for (final c in kids) {
      final d = zoteroData(c);
      final name = (d['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final path = prefix.isEmpty ? name : '$prefix / $name';
      final meta = (c['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
      out.add(
        ZoteroCollection(
          key: zoteroKey(c),
          name: name,
          parent: parent,
          itemCount: (meta['numItems'] as num?)?.toInt() ?? 0,
          path: path,
          depth: depth,
        ),
      );
      walk(zoteroKey(c), path, depth + 1);
    }
  }

  walk(null, '', 0);
  return out;
}

/// What the import is doing, for the dialog to word.
enum ZoteroPhase { library, items, attachments, importing, done }

class ZoteroProgress {
  const ZoteroProgress(
    this.phase, {
    this.title = '',
    this.done = 0,
    this.total = 0,
  });
  final ZoteroPhase phase;

  /// The item being imported ([ZoteroPhase.importing] only).
  final String title;
  final int done;
  final int total;
}

class ZoteroImportSummary {
  int papers = 0;
  int alreadyInLibrary = 0;
  int pdfs = 0;
  int pdfsFailed = 0;
  int highlights = 0;
  int notes = 0;
  int failedItems = 0;
  final Set<String> projects = {};
  bool cancelled = false;

  List<Object> _snapshot() => [
    papers,
    alreadyInLibrary,
    pdfs,
    pdfsFailed,
    highlights,
    notes,
    {...projects},
  ];

  void _restore(List<Object> s) {
    papers = s[0] as int;
    alreadyInLibrary = s[1] as int;
    pdfs = s[2] as int;
    pdfsFailed = s[3] as int;
    highlights = s[4] as int;
    notes = s[5] as int;
    projects
      ..clear()
      ..addAll(s[6] as Set<String>);
  }

  /// In English, for tests; the dialog words it with [messageFor].
  String get message => messageFor(lookupAppLocalizations(const Locale('en')));

  String messageFor(AppLocalizations l10n) {
    var s = l10n.zoteroSummaryMain(papers, pdfs, highlights, projects.length);
    if (notes > 0) s += '; ${l10n.zoteroSummaryNotes(notes)}';
    if (alreadyInLibrary > 0) {
      s += '; ${l10n.zoteroSummaryAlreadyIn(alreadyInLibrary)}';
    }
    if (pdfsFailed > 0) s += '; ${l10n.zoteroSummaryPdfsFailed(pdfsFailed)}';
    if (failedItems > 0) s += '; ${l10n.zoteroSummarySkipped(failedItems)}';
    return cancelled ? l10n.zoteroSummaryStopped(s) : l10n.zoteroSummaryDone(s);
  }
}

/// Imports a Zotero library (or some of its collections) into the local
/// database. Safe to run again: papers dedupe through [findDuplicate],
/// highlights by page and quote, notes by text.
class ZoteroImporter {
  ZoteroImporter({
    required this.db,
    required this.client,
    PageSizeReader? pageSizes,
    PdfSaver? savePdf,
  }) : _pageSizes = pageSizes ?? readPageSizesWithPdfrx,
       _savePdf = savePdf ?? savePdfToAppStorage;

  final AppDatabase db;
  final ZoteroClient client;
  final PageSizeReader _pageSizes;
  final PdfSaver _savePdf;

  /// Collections to read, with their counts. Throws [ZoteroException].
  Future<List<ZoteroCollection>> loadCollections() async =>
      parseCollections(await client.collections());

  /// [collectionKeys] null means everything. A chosen collection brings its
  /// sub-collections along.
  Future<ZoteroImportSummary> run({
    Set<String>? collectionKeys,
    void Function(ZoteroProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final summary = ZoteroImportSummary();
    bool cancelled() => (isCancelled?.call() ?? false);
    void report(
      ZoteroPhase phase, {
      String title = '',
      int done = 0,
      int total = 0,
    }) => onProgress?.call(
      ZoteroProgress(phase, title: title, done: done, total: total),
    );

    report(ZoteroPhase.library);
    final collections = parseCollections(await client.collections());
    final byKey = {for (final c in collections) c.key: c};
    // Chosen collections plus everything beneath them.
    final inScope = <String>{};
    if (collectionKeys == null) {
      inScope.addAll(byKey.keys);
    } else {
      void add(String key) {
        if (!byKey.containsKey(key) || !inScope.add(key)) return;
        for (final c in collections) {
          if (c.parent == key) add(c.key);
        }
      }

      collectionKeys.forEach(add);
    }

    var items = await client.topItems(
      onPage: (n, t) => report(ZoteroPhase.items, done: n, total: t ?? 0),
    );
    if (collectionKeys != null) {
      items = [
        for (final i in items)
          if (_collectionsOf(i).any(inScope.contains)) i,
      ];
    }
    items = [
      for (final i in items)
        if (paperFromZoteroItem(i) != null) i,
    ];
    if (cancelled()) return summary..cancelled = true;

    final keys = {for (final i in items) zoteroKey(i)};
    report(ZoteroPhase.attachments);
    final attachments = [
      for (final a in await client.itemsOfType('attachment'))
        if (keys.contains(zoteroData(a)['parentItem'])) a,
    ];
    final pdfKeys = {
      for (final a in attachments)
        if (isPdfAttachment(a)) zoteroKey(a),
    };
    final annotations = pdfKeys.isEmpty
        ? <Map<String, dynamic>>[]
        : [
            for (final a in await client.itemsOfType('annotation'))
              if (pdfKeys.contains(zoteroData(a)['parentItem'])) a,
          ];
    final childNotes = [
      for (final n in await client.itemsOfType('note'))
        if (keys.contains(zoteroData(n)['parentItem'])) n,
    ];
    if (cancelled()) return summary..cancelled = true;

    for (var i = 0; i < items.length; i++) {
      if (cancelled()) {
        summary.cancelled = true;
        break;
      }
      final item = items[i];
      report(
        ZoteroPhase.importing,
        title: '${zoteroData(item)['title'] ?? ''}',
        done: i,
        total: items.length,
      );
      try {
        await _importItem(
          item,
          summary: summary,
          byKey: byKey,
          inScope: inScope,
          attachments: [
            for (final a in attachments)
              if (zoteroData(a)['parentItem'] == zoteroKey(item)) a,
          ],
          annotations: annotations,
          childNotes: [
            for (final n in childNotes)
              if (zoteroData(n)['parentItem'] == zoteroKey(item)) n,
          ],
        );
      } on ZoteroException catch (e) {
        // A key or connection problem will hit every remaining item too.
        if (e.problem != ZoteroProblem.notFound &&
            e.problem != ZoteroProblem.server) {
          rethrow;
        }
        summary.failedItems++;
      } catch (_) {
        summary.failedItems++;
      }
    }
    report(ZoteroPhase.done, done: items.length, total: items.length);
    return summary;
  }

  List<String> _collectionsOf(Map<String, dynamic> item) => [
    for (final c in (zoteroData(item)['collections'] as List? ?? const []))
      if (c is String) c,
  ];

  Future<void> _importItem(
    Map<String, dynamic> item, {
    required ZoteroImportSummary summary,
    required Map<String, ZoteroCollection> byKey,
    required Set<String> inScope,
    required List<Map<String, dynamic>> attachments,
    required List<Map<String, dynamic>> annotations,
    required List<Map<String, dynamic>> childNotes,
  }) async {
    final meta = paperFromZoteroItem(item)!;
    final existing = await findDuplicate(db, meta);

    // Network first, so a failed download leaves nothing half-written.
    String? savedPdf;
    String? pdfAttachmentKey;
    final pdfs = [
      for (final a in attachments)
        if (isPdfAttachment(a)) a,
    ];
    final needsPdf =
        existing == null ||
        existing.pdfPath == null ||
        !File(existing.pdfPath!).existsSync();
    if (needsPdf && pdfs.isNotEmpty) {
      for (final a in pdfs) {
        final bytes = await client.downloadFile(zoteroKey(a));
        if (bytes == null) continue;
        final name =
            (zoteroData(a)['filename'] as String?) ?? '${zoteroKey(a)}.pdf';
        savedPdf = await _savePdf(bytes, name);
        pdfAttachmentKey = zoteroKey(a);
        break;
      }
      if (savedPdf == null) summary.pdfsFailed++;
    }

    final before = summary._snapshot();
    try {
      final pdfPath = savedPdf ?? existing?.pdfPath;
      final hasFile = pdfPath != null && File(pdfPath).existsSync();
      final sizes = hasFile ? await _pageSizes(pdfPath) : null;

      await db.transaction(() async {
        late String id;
        if (existing != null) {
          id = existing.id;
          summary.alreadyInLibrary++;
          await fillMissingMetadata(db, id, meta);
        } else {
          id = const Uuid().v4();
          await db
              .into(db.papers)
              .insert(
                PapersCompanion.insert(
                  id: Value(id),
                  title: meta.title,
                  authors: Value(meta.authors),
                  year: Value(meta.year),
                  venue: Value(meta.venue),
                  doi: Value(meta.doi),
                  pmid: Value(meta.pmid),
                  url: Value(meta.url),
                  abstract: Value(meta.abstract),
                ),
              );
          summary.papers++;
        }
        if (savedPdf != null) {
          await (db.update(db.papers)..where((p) => p.id.equals(id))).write(
            PapersCompanion(
              pdfPath: Value(savedPdf),
              pageCount: sizes == null
                  ? const Value.absent()
                  : Value(sizes.length),
            ),
          );
          summary.pdfs++;
        }
        await ensureCitekey(db, id);

        for (final c in _collectionsOf(item)) {
          if (!inScope.contains(c)) continue;
          final projectId = await findOrCreateProject(db, byKey[c]!.path);
          await addPaperToProject(db, projectId: projectId, paperId: id);
          summary.projects.add(byKey[c]!.path);
        }

        // Annotations of every PDF attachment; sizes belong to the file we
        // hold, so they only apply to the attachment it came from (or, for
        // a paper we already had, are unknown).
        final lines = <String>[];
        final known = await (db.select(
          db.highlights,
        )..where((h) => h.paperId.equals(id))).get();
        final seen = {for (final h in known) '${h.pageNumber}\u0000${h.quote}'};
        for (final a in annotations) {
          final parent = zoteroData(a)['parentItem'];
          if (!pdfs.any((p) => zoteroKey(p) == parent)) continue;
          final ann = annotationFromZotero(a);
          if (ann == null) continue;
          if (ann.type == 'note') {
            final text = ann.comment.isNotEmpty ? ann.comment : ann.text;
            if (text.isNotEmpty) lines.add('p. ${ann.page}: $text');
            continue;
          }
          if (ann.text.isEmpty) continue;
          if (!seen.add('${ann.page}\u0000${cleanQuote(ann.text)}')) continue;
          final usable =
              parent == pdfAttachmentKey ||
              (pdfAttachmentKey == null && pdfs.length == 1);
          final size = usable && sizes != null && ann.page <= sizes.length
              ? sizes[ann.page - 1]
              : null;
          await db
              .into(db.highlights)
              .insert(
                HighlightsCompanion.insert(
                  paperId: id,
                  pageNumber: ann.page,
                  quote: cleanQuote(ann.text),
                  rectsJson: encodeRects(rectsToFractions(ann.rects, size)),
                  colorHex: Value(colorToHex(nearestInk(ann.color))),
                  comment: Value(ann.comment.isEmpty ? null : ann.comment),
                ),
              );
          summary.highlights++;
        }
        for (final n in childNotes) {
          final text = htmlToPlainText(zoteroData(n)['note'] as String? ?? '');
          if (text.isNotEmpty) lines.add(text);
        }
        if (lines.isNotEmpty) {
          summary.notes += await _appendNotes(id, meta.title, lines);
        }
      });
    } catch (_) {
      summary._restore(before);
      // Nothing was committed; don't leave the download orphaned.
      if (savedPdf != null) {
        try {
          await File(savedPdf).delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Adds [lines] not already present to the paper's "Zotero notes" note,
  /// creating and linking it first. Returns 1 if anything was added.
  Future<int> _appendNotes(
    String paperId,
    String title,
    List<String> lines,
  ) async {
    final noteTitle = 'Zotero notes: $title';
    final refs = await (db.select(
      db.notePaperRefs,
    )..where((r) => r.paperId.equals(paperId))).get();
    Note? note;
    for (final r in refs) {
      final n = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(r.noteId))).getSingleOrNull();
      if (n != null && n.title == noteTitle) note = n;
    }
    if (note != null && isLockedContent(note.content)) return 0;
    final doc = decodeNoteContent(note?.content ?? '');
    final present = doc.toPlainText();
    final fresh = [
      for (final l in lines)
        if (!present.contains(l)) l,
    ];
    if (fresh.isEmpty) return 0;
    for (final l in fresh) {
      doc.insert(doc.length - 1, '$l\n');
    }
    final content = encodeNoteContent(doc);
    if (note == null) {
      final id = const Uuid().v4();
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: Value(id),
              title: Value(noteTitle),
              content: Value(content),
            ),
          );
      await db
          .into(db.notePaperRefs)
          .insert(NotePaperRefsCompanion.insert(noteId: id, paperId: paperId));
    } else {
      await (db.update(db.notes)..where((n) => n.id.equals(note!.id))).write(
        NotesCompanion(
          content: Value(content),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    return 1;
  }
}
