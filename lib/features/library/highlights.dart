import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'annotations_providers.dart';

export 'annotations_providers.dart' show colorFromHex, colorToHex;

/// Soft highlighter inks, shared by text highlights and freeform ink.
const highlightInks = [
  Color(0xFFF2D66B), // butter
  Color(0xFF9CC79A), // sage
  Color(0xFFEBA9A4), // rose
  Color(0xFF9DC3DE), // mist blue
];

/// Merges per-character boxes (already in Flutter coordinates, y down) into
/// one box per line, then expresses them as fractions of [pageSize]. Empty
/// boxes (spaces, line breaks) are skipped; characters whose vertical
/// extents overlap by more than half the shorter one share a line.
List<Rect> lineRects(Iterable<Rect> charRects, Size pageSize) {
  final chars = charRects.where((r) => r.width > 0 && r.height > 0).toList()
    ..sort(
      (a, b) =>
          a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left),
    );
  final lines = <Rect>[];
  for (final r in chars) {
    final i = lines.indexWhere((line) {
      final overlap =
          math.min(line.bottom, r.bottom) - math.max(line.top, r.top);
      return overlap > math.min(line.height, r.height) / 2;
    });
    if (i < 0) {
      lines.add(r);
    } else {
      lines[i] = lines[i].expandToInclude(r);
    }
  }
  return [
    for (final l in lines)
      Rect.fromLTRB(
        l.left / pageSize.width,
        l.top / pageSize.height,
        l.right / pageSize.width,
        l.bottom / pageSize.height,
      ),
  ];
}

String encodeRects(List<Rect> rects) => jsonEncode([
  for (final r in rects)
    [
      for (final v in [r.left, r.top, r.right, r.bottom])
        (v * 10000).round() / 10000,
    ],
]);

List<Rect> decodeRects(String json) {
  try {
    return [
      for (final r in jsonDecode(json) as List)
        Rect.fromLTRB(
          (r[0] as num).toDouble(),
          (r[1] as num).toDouble(),
          (r[2] as num).toDouble(),
          (r[3] as num).toDouble(),
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// Collapses the PDF's hard line breaks and hyphenation so a quote reads
/// as the sentence it is ("trans-\nformer" → "transformer").
String cleanQuote(String raw) => raw
    .replaceAllMapped(RegExp(r'(\w)-\s*\n\s*(\w)'), (m) => '${m[1]}${m[2]}')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Future<String> addHighlight(
  AppDatabase db, {
  required String paperId,
  required int pageNumber,
  required String quote,
  required List<Rect> rects,
  required Color color,
}) async {
  final id = const Uuid().v4();
  await db
      .into(db.highlights)
      .insert(
        HighlightsCompanion.insert(
          id: Value(id),
          paperId: paperId,
          pageNumber: pageNumber,
          quote: cleanQuote(quote),
          rectsJson: encodeRects(rects),
          colorHex: Value(colorToHex(color)),
        ),
      );
  return id;
}

Future<void> updateHighlight(
  AppDatabase db,
  String id, {
  Color? color,
  String? comment,
}) => (db.update(db.highlights)..where((h) => h.id.equals(id))).write(
  HighlightsCompanion(
    colorHex: color == null ? const Value.absent() : Value(colorToHex(color)),
    comment: comment == null
        ? const Value.absent()
        : Value(comment.trim().isEmpty ? null : comment.trim()),
  ),
);

Future<void> deleteHighlight(AppDatabase db, String id) =>
    (db.delete(db.highlights)..where((h) => h.id.equals(id))).go();

/// Remembers where the reader stopped. Not an "edit" worth a sync of its
/// own every page flip — but it does sync, so the paper reopens at the same
/// page on another device.
Future<void> saveLastPage(AppDatabase db, String paperId, int page) =>
    (db.update(db.papers)..where(
          // `NOT (NULL = x)` is NULL in SQL, so a never-opened paper needs
          // its own case.
          (p) =>
              p.id.equals(paperId) &
              (p.lastPage.isNull() | p.lastPage.equals(page).not()),
        ))
        .write(PapersCompanion(lastPage: Value(page)));

final highlightsForPaperProvider = StreamProvider.autoDispose
    .family<List<Highlight>, String>((ref, paperId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.highlights)
            ..where((h) => h.paperId.equals(paperId))
            ..orderBy([
              (h) => OrderingTerm.asc(h.pageNumber),
              (h) => OrderingTerm.asc(h.createdAt),
            ]))
          .watch();
    });

/// A link to a page of a paper, used for "p. 12" references in quotes:
/// `corplex://paper/<paperId>?page=12`.
String paperPageLink(String paperId, int page) =>
    'corplex://paper/$paperId?page=$page';

({String paperId, int page})? parsePaperPageLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'corplex' ||
      uri.host != 'paper' ||
      uri.pathSegments.length != 1) {
    return null;
  }
  final page = int.tryParse(uri.queryParameters['page'] ?? '1');
  if (page == null || page < 1) return null;
  return (paperId: uri.pathSegments.single, page: page);
}
