import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/share_origin.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'annotated_pdf.dart';
import 'annotations_providers.dart' show colorFromHex, decodeStrokePoints;
import 'highlights.dart' show decodeRects;

/// Whether the paper has anything to write into a PDF (a highlight or ink
/// stroke). Drives the paper screen's "Export with highlights" menu item.
final paperHasMarksProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  paperId,
) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM highlights WHERE paper_id = ?1) + '
        '(SELECT COUNT(*) FROM annotations WHERE paper_id = ?1) AS n',
        variables: [Variable.withString(paperId)],
        readsFrom: {db.highlights, db.annotations},
      )
      .watchSingle()
      .map((r) => r.read<int>('n') > 0);
});

/// The marks stored for [paperId], ready for [writeAnnotatedPdf].
Future<({List<HighlightMark> highlights, List<InkMark> ink})> loadMarks(
  AppDatabase db,
  String paperId,
) async {
  final hs = await (db.select(
    db.highlights,
  )..where((h) => h.paperId.equals(paperId))).get();
  final as = await (db.select(
    db.annotations,
  )..where((a) => a.paperId.equals(paperId))).get();
  return (
    highlights: [
      for (final h in hs)
        HighlightMark(
          page: h.pageNumber,
          rects: [
            for (final r in decodeRects(h.rectsJson))
              [r.left, r.top, r.right, r.bottom],
          ],
          rgb: colorFromHex(h.colorHex).toARGB32() & 0xFFFFFF,
          comment: h.comment,
        ),
    ],
    ink: [
      for (final a in as)
        InkMark(
          page: a.pageNumber,
          points: [
            for (final p in decodeStrokePoints(a.pointsJson)) [p.dx, p.dy],
          ],
          rgb: colorFromHex(a.colorHex).toARGB32() & 0xFFFFFF,
        ),
    ],
  );
}

String annotatedFileName(String title) {
  final clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final base = clean.isEmpty ? 'Paper' : clean;
  return '${base.length > 120 ? base.substring(0, 120) : base} (annotated).pdf';
}

class _Job {
  _Job(this.pdf, this.highlights, this.ink);
  final Uint8List pdf;
  final List<HighlightMark> highlights;
  final List<InkMark> ink;
}

AnnotatedPdfResult _run(_Job j) =>
    writeAnnotatedPdf(j.pdf, highlights: j.highlights, ink: j.ink);

/// Writes an annotated copy of [paper]'s PDF and opens the share sheet. The
/// stored PDF is never modified.
Future<void> exportAnnotatedPdf(
  BuildContext context,
  WidgetRef ref,
  Paper paper,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final origin = shareOrigin(context);
  final db = ref.read(databaseProvider);
  void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  final path = paper.pdfPath;
  if (path == null || !File(path).existsSync()) {
    say('This paper’s PDF isn’t on this device.');
    return;
  }
  try {
    final marks = await loadMarks(db, paper.id);
    final pdf = await File(path).readAsBytes();
    final result = await compute(_run, _Job(pdf, marks.highlights, marks.ink));
    if (result.written == 0) {
      say('Nothing to export: the marks don’t match this PDF’s pages.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final out = Directory('${dir.path}/annotated_export')
      ..createSync(recursive: true);
    final file = File('${out.path}/${annotatedFileName(paper.title)}');
    await file.writeAsBytes(result.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: paper.title,
        sharePositionOrigin: origin,
      ),
    );
  } on AnnotatedPdfException catch (e) {
    say(e.message);
  } catch (_) {
    say('Couldn’t export this PDF.');
  }
}
