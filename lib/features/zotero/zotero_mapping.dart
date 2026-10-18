import 'dart:convert';
import 'dart:ui';

import '../library/authors.dart';
import '../library/bibtex.dart';
import '../library/highlights.dart';

/// Item types that are never papers in their own right.
const zoteroNonPaperTypes = {'note', 'attachment', 'annotation'};

Map<String, dynamic> zoteroData(Map<String, dynamic> item) =>
    (item['data'] as Map?)?.cast<String, dynamic>() ?? const {};

String zoteroKey(Map<String, dynamic> item) =>
    (item['key'] ?? zoteroData(item)['key'] ?? '') as String;

String? _s(Map<String, dynamic> d, String k) {
  final v = d[k];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Paper metadata for a top-level Zotero item, or null for notes,
/// attachments and untitled items.
PaperMetadata? paperFromZoteroItem(Map<String, dynamic> item) {
  final d = zoteroData(item);
  final type = _s(d, 'itemType');
  if (type == null || zoteroNonPaperTypes.contains(type)) return null;
  final title = _s(d, 'title') ?? _s(d, 'caseName') ?? _s(d, 'subject');
  if (title == null) return null;

  final creators = [
    for (final c in (d['creators'] as List? ?? const []))
      if (c is Map) c.cast<String, dynamic>(),
  ];
  List<Map<String, dynamic>> pick(String type) => [
    for (final c in creators)
      if ((c['creatorType'] ?? 'author') == type) c,
  ];
  var chosen = pick('author');
  if (chosen.isEmpty) chosen = pick('editor');
  if (chosen.isEmpty) chosen = creators;
  final authors = <Author>[
    for (final c in chosen)
      if (_s(c, 'name') != null)
        Author(family: _s(c, 'name')!)
      else if (_s(c, 'lastName') != null || _s(c, 'firstName') != null)
        Author(
          family: _s(c, 'lastName') ?? _s(c, 'firstName')!,
          given: _s(c, 'lastName') == null ? '' : (_s(c, 'firstName') ?? ''),
        ),
  ];

  String? venue;
  for (final k in const [
    'publicationTitle',
    'proceedingsTitle',
    'bookTitle',
    'university',
    'institution',
    'repository',
    'publisher',
  ]) {
    venue = _s(d, k);
    if (venue != null) break;
  }

  return PaperMetadata(
    title: title,
    authors: authorsToStored(AuthorList(authors)),
    year: yearFromZoteroDate(_s(d, 'date')),
    venue: venue,
    doi: _doiOf(d),
  );
}

int? yearFromZoteroDate(String? date) {
  if (date == null) return null;
  final m = RegExp(r'(?<!\d)(1[5-9]\d\d|20\d\d)(?!\d)').firstMatch(date);
  return m == null ? null : int.parse(m.group(1)!);
}

String? _doiOf(Map<String, dynamic> d) {
  final direct = _s(d, 'DOI');
  if (direct != null) return direct;
  final doi = RegExp(r'10\.\d{4,9}/[^\s"<>]+');
  final extra = RegExp(
    r'^DOI:\s*(\S+)',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(_s(d, 'extra') ?? '');
  if (extra != null) return extra.group(1);
  final url = _s(d, 'url');
  if (url != null && url.contains('doi.org/')) {
    return doi.firstMatch(Uri.decodeFull(url))?.group(0);
  }
  return null;
}

bool isPdfAttachment(Map<String, dynamic> item) {
  final d = zoteroData(item);
  return d['itemType'] == 'attachment' &&
      d['contentType'] == 'application/pdf' &&
      (d['linkMode'] == 'imported_file' || d['linkMode'] == 'imported_url');
}

/// A Zotero annotation, reduced to what a [Highlights] row needs.
class ZoteroAnnotation {
  const ZoteroAnnotation({
    required this.type,
    required this.page,
    required this.text,
    required this.comment,
    required this.color,
    required this.rects,
  });

  final String type; // highlight | underline | note
  final int page; // 1-based
  final String text;
  final String comment;
  final String? color;

  /// `[x1, y1, x2, y2]` in PDF points, y measured from the page bottom.
  final List<List<double>> rects;
}

ZoteroAnnotation? annotationFromZotero(Map<String, dynamic> item) {
  final d = zoteroData(item);
  if (d['itemType'] != 'annotation') return null;
  final type = _s(d, 'annotationType');
  if (type != 'highlight' && type != 'underline' && type != 'note') {
    return null; // image and ink have no text to keep
  }
  var page = 1;
  final rects = <List<double>>[];
  try {
    final raw = d['annotationPosition'];
    final pos = raw is String ? jsonDecode(raw) : raw;
    if (pos is Map) {
      final idx = pos['pageIndex'];
      if (idx is num) page = idx.toInt() + 1;
      for (final r in (pos['rects'] as List? ?? const [])) {
        if (r is List && r.length >= 4 && r.every((v) => v is num)) {
          rects.add([for (final v in r.take(4)) (v as num).toDouble()]);
        }
      }
    }
  } catch (_) {}
  return ZoteroAnnotation(
    type: type!,
    page: page < 1 ? 1 : page,
    text: (_s(d, 'annotationText') ?? '').replaceAll(RegExp(r'\s+'), ' '),
    comment: _s(d, 'annotationComment') ?? '',
    color: _s(d, 'annotationColor'),
    rects: rects,
  );
}

/// Zotero rects (points, origin bottom-left) as page fractions (origin
/// top-left), clamped to the page. Empty when the page size is unknown.
List<Rect> rectsToFractions(List<List<double>> rects, Size? page) {
  if (page == null || page.width <= 0 || page.height <= 0) return const [];
  double c(double v) => v.clamp(0.0, 1.0);
  return [
    for (final r in rects)
      Rect.fromLTRB(
        c(r[0] / page.width),
        c(1 - r[3] / page.height),
        c(r[2] / page.width),
        c(1 - r[1] / page.height),
      ),
  ];
}

/// The nearest of the app's highlighter inks to a Zotero `#rrggbb`.
Color nearestInk(String? hex) {
  if (hex == null) return highlightInks.first;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (m == null) return highlightInks.first;
  final v = int.parse(m.group(1)!, radix: 16);
  final r = (v >> 16) & 0xff, g = (v >> 8) & 0xff, b = v & 0xff;
  var best = highlightInks.first;
  var bestD = double.infinity;
  for (final ink in highlightInks) {
    final dr = r - (ink.r * 255).round();
    final dg = g - (ink.g * 255).round();
    final db = b - (ink.b * 255).round();
    final dist = (dr * dr + dg * dg + db * db).toDouble();
    if (dist < bestD) {
      bestD = dist;
      best = ink;
    }
  }
  return best;
}

/// Plain text from a Zotero note's HTML: paragraph and list structure
/// becomes line breaks, entities are decoded.
String htmlToPlainText(String html) {
  var s = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(
          r'</\s*(p|div|h[1-6]|li|tr|blockquote)\s*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final n = int.parse(m.group(1)!);
        return n > 0 && n < 0x110000 ? String.fromCharCode(n) : '';
      })
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
        final n = int.parse(m.group(1)!, radix: 16);
        return n > 0 && n < 0x110000 ? String.fromCharCode(n) : '';
      })
      .replaceAll('&amp;', '&');
  return s
      .split('\n')
      .map((l) => l.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
