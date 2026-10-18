/// Where a comment's passage is now: [start, end) in the editor document.
typedef CommentSpan = ({int start, int end});

/// Finds [quote] in [text] (the editor document's plain text, in which an
/// embed is one character, so offsets are document offsets).
///
/// The occurrence nearest to [anchor] wins when it appears more than once;
/// an exact match is preferred to a case-insensitive one. Null when the
/// passage is gone ("Passage changed").
CommentSpan? locateQuote(String text, String quote, int anchor) {
  if (quote.isEmpty) return null;
  CommentSpan? nearest(String hay, String needle) {
    var best = -1;
    var from = 0;
    while (true) {
      final i = hay.indexOf(needle, from);
      if (i < 0) break;
      if (best < 0 || (i - anchor).abs() < (best - anchor).abs()) best = i;
      from = i + 1;
    }
    return best < 0 ? null : (start: best, end: best + needle.length);
  }

  final exact = nearest(text, quote);
  if (exact != null) return exact;
  final lower = text.toLowerCase();
  // Lower-casing can change a string's length (rare scripts); then offsets
  // wouldn't line up, so skip the loose match.
  if (lower.length != text.length) return null;
  return nearest(lower, quote.toLowerCase());
}

/// A passage for display: embed placeholders become an ellipsis and
/// whitespace is collapsed.
String displayQuote(String quote) =>
    quote.replaceAll('￼', '…').replaceAll(RegExp(r'\s+'), ' ').trim();
