import 'csl_rich.dart';

/// Text helpers for the CSL engine: case transforms, period stripping and
/// page ranges.

const _stopWords = {
  'a',
  'an',
  'and',
  'as',
  'at',
  'but',
  'by',
  'down',
  'for',
  'from',
  'in',
  'into',
  'nor',
  'of',
  'on',
  'onto',
  'or',
  'over',
  'so',
  'the',
  'till',
  'to',
  'up',
  'via',
  'with',
  'yet',
  'vs',
  'v',
};

String _upperFirst(String s) =>
    s.isEmpty ? s : s.substring(0, 1).toUpperCase() + s.substring(1);

bool _hasInnerUpper(String w) => RegExp(r'.[A-Z]').hasMatch(w);

/// Applies a CSL `text-case` to [s].
String applyTextCase(String s, String mode) {
  switch (mode) {
    case 'lowercase':
      return s.toLowerCase();
    case 'uppercase':
      return s.toUpperCase();
    case 'capitalize-first':
      final i = s.indexOf(RegExp(r'\S'));
      if (i < 0) return s;
      // Leave a first word that already has capitals inside ("arXiv").
      final word = s.substring(i).split(RegExp(r'\s')).first;
      if (_hasInnerUpper(word)) return s;
      return s.substring(0, i) + _upperFirst(s.substring(i));
    case 'capitalize-all':
      return s.replaceAllMapped(
        RegExp(r'(^|[\s\-–(“"])([^\s\-–(“"])'),
        (m) => '${m[1]}${m[2]!.toUpperCase()}',
      );
    case 'sentence':
      // Only fixes shouting: an all-caps title becomes sentence case.
      if (s.toUpperCase() == s && s.toLowerCase() != s) {
        return applyTextCase(s.toLowerCase(), 'capitalize-first');
      }
      return s;
    case 'title':
      if (s.toUpperCase() == s && s.toLowerCase() != s) s = s.toLowerCase();
      final words = s.split(' ');
      var afterBreak = true;
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        if (w.isEmpty) continue;
        final bare = w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        final isStop = _stopWords.contains(bare);
        final last = i == words.length - 1;
        if (!_hasInnerUpper(w) && (afterBreak || last || !isStop)) {
          words[i] = _upperFirst(w);
        }
        afterBreak = w.endsWith(':') || w.endsWith('?') || w.endsWith('.');
      }
      return words.join(' ');
  }
  return s;
}

/// Applies [mode] across spans, keeping their styling.
List<CslSpan> caseSpans(List<CslSpan> spans, String mode) {
  final full = spans.map((s) => s.text).join();
  final out = applyTextCase(full, mode);
  if (out.length == full.length) {
    var at = 0;
    return [
      for (final s in spans) s.withText(out.substring(at, at += s.text.length)),
    ];
  }
  return [
    for (var i = 0; i < spans.length; i++)
      i == 0 ? spans[i].withText(out) : spans[i].withText(''),
  ];
}

String stripPeriods(String s) => s.replaceAll('.', '');

bool _digits(String s) => RegExp(r'^\d+$').hasMatch(s);

/// A page range in the requested `page-range-format`.
String formatPages(String value, String? format) {
  return value
      .replaceAllMapped(RegExp(r'(\d+)\s*[-–—]\s*(\d+)'), (m) {
        final a = m[1]!;
        var b = m[2]!;
        if (!_digits(a) || !_digits(b) || b.length > a.length) {
          return '$a–$b';
        }
        // Pad the end to the start's length ("321–28" means 328).
        if (b.length < a.length) b = a.substring(0, a.length - b.length) + b;
        String minimal(int keep) {
          var i = 0;
          while (i < a.length - 1 && a[i] == b[i]) {
            i++;
          }
          final start = (a.length - i) < keep ? a.length - keep : i;
          return b.substring(start < 0 ? 0 : start);
        }

        switch (format) {
          case 'expanded':
            return '$a–$b';
          case 'minimal':
            return '$a–${minimal(1)}';
          case 'minimal-two':
            return '$a–${minimal(2)}';
          case 'chicago':
          case 'chicago-15':
          case 'chicago-16':
            final n = int.parse(a);
            if (n < 100 || n % 100 == 0) return '$a–$b';
            if (n % 100 < 10) return '$a–${minimal(1)}';
            final short = minimal(2);
            if (a.length >= 4 && short.length > 2) return '$a–$b';
            return '$a–$short';
        }
        return '$a–$b';
      })
      .replaceAll(RegExp(r'(?<=\d)\s*-\s*(?=\d)'), '–');
}

/// Whether a value counts as a number for `is-numeric` (a number, a range,
/// a list, optionally with letters attached such as "12a").
bool isNumericValue(String v) => RegExp(
  r'^\s*[A-Za-z]?\d+[A-Za-z]?(\s*[,&\-–]\s*[A-Za-z]?\d+[A-Za-z]?)*\s*$',
).hasMatch(v);

String romanNumeral(int n) {
  if (n <= 0 || n >= 4000) return '$n';
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms = [
    'm',
    'cm',
    'd',
    'cd',
    'c',
    'xc',
    'l',
    'xl',
    'x',
    'ix',
    'v',
    'iv',
    'i',
  ];
  var r = '';
  var left = n;
  for (var i = 0; i < values.length; i++) {
    while (left >= values[i]) {
      r += syms[i];
      left -= values[i];
    }
  }
  return r;
}
