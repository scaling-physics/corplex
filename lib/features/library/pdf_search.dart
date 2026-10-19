import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/l10n.dart';

/// Where find-in-document gets its text. The PDF's own text layer is one
/// source ([PdfrxTextSource]); a later one (OCR of scanned pages) only has
/// to answer the same question: where on page N does [query] appear?
abstract class PageTextSource {
  int get pageCount;

  /// Boxes of every case-insensitive occurrence of [query] on [page]
  /// (1-based), as fractions of the page (0..1, origin top-left), one
  /// rect per match in reading order. Empty when the page has no text.
  Future<List<Rect>> find(int page, String query);
}

/// One hit: the page and its box as page fractions.
class SearchMatch {
  const SearchMatch(this.page, this.rect);
  final int page;
  final Rect rect;
}

/// Searches a document through a [PageTextSource], page by page (so
/// results appear as they are found), and tracks the current match.
///
/// The UI and the page marks only know this class, so any text source
/// plugs in. [onReveal] is called whenever the current match changes and
/// should be scrolled into view.
class DocumentSearch extends ChangeNotifier {
  DocumentSearch(this.source, {this.incomplete});

  /// Whether the source may still be missing text (a scan being read), so
  /// the count is shown as a lower bound.
  final bool Function()? incomplete;

  final PageTextSource source;
  void Function(SearchMatch match)? onReveal;

  String _query = '';
  int _session = 0;
  bool _busy = false;
  bool _disposed = false;
  List<SearchMatch> _matches = const [];
  Map<int, List<int>> _byPage = const {};
  int? _current;

  String get query => _query;
  bool get busy => _busy;
  List<SearchMatch> get matches => _matches;

  /// Index into [matches] of the emphasised match, or null.
  int? get current => _current;

  /// Indices (into [matches]) of the matches on [page].
  List<int> indicesOnPage(int page) => _byPage[page] ?? const [];

  /// Starts (or restarts) a search. An empty query clears the results.
  Future<void> search(String query) async {
    final session = ++_session;
    _query = query.trim();
    _matches = const [];
    _byPage = const {};
    _current = null;
    _busy = _query.isNotEmpty;
    notifyListeners();
    if (_query.isEmpty) return;

    final found = <SearchMatch>[];
    final byPage = <int, List<int>>{};
    for (var page = 1; page <= source.pageCount; page++) {
      List<Rect> rects;
      try {
        rects = await source.find(page, _query);
      } catch (_) {
        rects = const [];
      }
      if (session != _session || _disposed) return;
      if (rects.isEmpty) continue;
      for (final r in rects) {
        byPage.putIfAbsent(page, () => []).add(found.length);
        found.add(SearchMatch(page, r));
      }
      _matches = List.unmodifiable(found);
      _byPage = {for (final e in byPage.entries) e.key: List.of(e.value)};
      final first = _current == null;
      if (first) _current = 0;
      notifyListeners();
      if (first) onReveal?.call(found.first);
    }
    if (session != _session || _disposed) return;
    _busy = false;
    notifyListeners();
  }

  /// Next match, wrapping from the last to the first.
  void next() => _step(1);

  /// Previous match, wrapping from the first to the last.
  void previous() => _step(-1);

  void _step(int delta) {
    if (_matches.isEmpty) return;
    final at = _current ?? (delta > 0 ? -1 : 0);
    _current = (at + delta) % _matches.length;
    notifyListeners();
    onReveal?.call(_matches[_current!]);
  }

  /// "3 of 41", "No matches", or "" before anything is typed.
  String get summary => summaryIn(lookupAppLocalizations(const Locale('en')));

  /// [summary] in [l]'s language.
  String summaryIn(AppLocalizations l) {
    if (_query.isEmpty) return '';
    final more = _busy || (incomplete?.call() ?? false);
    if (_matches.isEmpty) {
      if (_busy) return l.viewerFindSearching;
      return more ? l.viewerFindNoMatchesYet : l.viewerFindNoMatches;
    }
    final at = _current! + 1;
    return more
        ? l.viewerFindCountMore(at, _matches.length)
        : l.viewerFindCount(at, _matches.length);
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    super.dispose();
  }
}

/// The PDF's text layer, through pdfrx.
class PdfrxTextSource implements PageTextSource {
  PdfrxTextSource(this.controller);

  final PdfViewerController controller;
  final _text = <int, PdfPageText>{};

  @override
  int get pageCount =>
      controller.isReady ? controller.document.pages.length : 0;

  @override
  Future<List<Rect>> find(int page, String query) async {
    final doc = controller.document;
    final pdfPage = doc.pages[page - 1];
    final text = _text[page] ??= await pdfPage.loadStructuredText();
    final size = PdfRect(
      0,
      pdfPage.height,
      pdfPage.width,
      0,
    ).toRect(page: pdfPage).size;
    final out = <Rect>[];
    await for (final m in text.allMatches(query, caseInsensitive: true)) {
      final r = m.bounds.toRect(page: pdfPage);
      out.add(
        Rect.fromLTRB(
          r.left / size.width,
          r.top / size.height,
          r.right / size.width,
          r.bottom / size.height,
        ),
      );
    }
    return out;
  }
}

/// Paints the matches on one page; the current one is emphasised. Only
/// built while a search is open, and repaints on its own.
class SearchMarks extends StatelessWidget {
  const SearchMarks({
    super.key,
    required this.search,
    required this.page,
    required this.pageRect,
  });

  final DocumentSearch search;
  final int page;
  final Rect pageRect;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Positioned.fromRect(
      rect: pageRect,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: search,
          builder: (context, _) {
            final on = search.indicesOnPage(page);
            if (on.isEmpty) return const SizedBox.shrink();
            return CustomPaint(
              painter: _MarksPainter(
                rects: [for (final i in on) search.matches[i].rect],
                current: [
                  for (var k = 0; k < on.length; k++)
                    if (on[k] == search.current) k,
                ].firstOrNull,
                soft: c.tertiary.withValues(alpha: 0.35),
                strong: c.primary.withValues(alpha: 0.5),
                ring: c.primary,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.rects,
    required this.current,
    required this.soft,
    required this.strong,
    required this.ring,
  });

  final List<Rect> rects;
  final int? current;
  final Color soft, strong, ring;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      final box = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      ).inflate(1);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(2));
      if (i == current) {
        canvas.drawRRect(rr, Paint()..color = strong);
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = ring,
        );
      } else {
        canvas.drawRRect(rr, Paint()..color = soft);
      }
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true; // few rects, rebuilt on change
}
