import 'package:flutter/material.dart';

import '../ocr/ocr_engine.dart';
import 'pdf_search.dart';

/// Boxes of every occurrence of [query] in recognised text, as page
/// fractions. A phrase matches across adjacent words (the first may end
/// the phrase's first word, the last may start its last word); a one-word
/// query matches inside words. A phrase that wraps onto the next line is
/// boxed on the line it starts on.
List<Rect> findInOcr(OcrPageText page, String query) {
  final tokens = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return const [];
  final words = page.words.toList();
  final lower = [for (final w in words) w.text.toLowerCase()];
  final out = <Rect>[];
  for (var i = 0; i + tokens.length <= words.length; i++) {
    var ok = true;
    for (var k = 0; k < tokens.length && ok; k++) {
      final w = lower[i + k];
      final t = tokens[k];
      if (tokens.length == 1) {
        ok = w.contains(t);
      } else if (k == 0) {
        ok = w.endsWith(t);
      } else if (k == tokens.length - 1) {
        ok = w.startsWith(t);
      } else {
        ok = w == t;
      }
    }
    if (!ok) continue;
    var box = _box(words[i]);
    for (var k = 1; k < tokens.length; k++) {
      final next = _box(words[i + k]);
      if (_sameLine(box, next)) box = box.expandToInclude(next);
    }
    out.add(box);
  }
  return out;
}

Rect _box(OcrWord w) => Rect.fromLTRB(w.left, w.top, w.right, w.bottom);

bool _sameLine(Rect a, Rect b) {
  final overlap =
      (a.bottom < b.bottom ? a.bottom : b.bottom) -
      (a.top > b.top ? a.top : b.top);
  return overlap > (a.height < b.height ? a.height : b.height) / 2;
}

/// Find in a scanned paper: the text layer answers first; a page where it
/// finds nothing is looked up in the stored OCR text (which only exists for
/// pages that have no text layer). Pages not recognised yet have no
/// matches, which [incomplete] lets the search bar admit.
class OcrFallbackSource implements PageTextSource {
  OcrFallbackSource(this.primary, this.recognised, {this.stillReading});

  final PageTextSource primary;

  /// Recognised text of a 1-based page, or null.
  final Future<OcrPageText?> Function(int page) recognised;

  /// True while recognition for the paper is still running.
  final bool Function()? stillReading;

  bool get incomplete => stillReading?.call() ?? false;

  @override
  int get pageCount => primary.pageCount;

  @override
  Future<List<Rect>> find(int page, String query) async {
    final hits = await primary.find(page, query);
    if (hits.isNotEmpty) return hits;
    final text = await recognised(page);
    return text == null ? const [] : findInOcr(text, query);
  }
}
