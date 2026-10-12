/// Formatted output of the CSL processor: a run of text with the few
/// character styles CSL can ask for.
class CslSpan {
  const CslSpan(
    this.text, {
    this.italic = false,
    this.bold = false,
    this.smallCaps = false,
    this.underline = false,
    this.vAlign = 0,
  });

  final String text;
  final bool italic;
  final bool bold;
  final bool smallCaps;
  final bool underline;

  /// 0 baseline, 1 superscript, -1 subscript.
  final int vAlign;

  CslSpan withText(String t) => CslSpan(
    t,
    italic: italic,
    bold: bold,
    smallCaps: smallCaps,
    underline: underline,
    vAlign: vAlign,
  );

  CslSpan copyWith({
    bool? italic,
    bool? bold,
    bool? smallCaps,
    bool? underline,
    int? vAlign,
  }) => CslSpan(
    text,
    italic: italic ?? this.italic,
    bold: bold ?? this.bold,
    smallCaps: smallCaps ?? this.smallCaps,
    underline: underline ?? this.underline,
    vAlign: vAlign ?? this.vAlign,
  );

  bool sameStyle(CslSpan o) =>
      italic == o.italic &&
      bold == o.bold &&
      smallCaps == o.smallCaps &&
      underline == o.underline &&
      vAlign == o.vAlign;
}

const _sup = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '+': '⁺',
  '-': '⁻',
  '(': '⁽',
  ')': '⁾',
};

/// Styled text produced by the processor.
class CslRich {
  const CslRich(this.spans);

  static const empty = CslRich([]);

  final List<CslSpan> spans;

  bool get isEmpty => plain.trim().isEmpty;

  /// The text without any styling.
  String get plain => spans.map((s) => s.text).join();

  /// Text for places that can't style (plain-text export, a list tile):
  /// superscripts become Unicode superscript digits.
  String get plainWithSuperscripts => spans
      .map(
        (s) => s.vAlign == 1
            ? s.text.split('').map((c) => _sup[c] ?? c).join()
            : s.text,
      )
      .join();

  /// Markdown with `*italic*` and `**bold**`.
  String toMarkdown() {
    final b = StringBuffer();
    for (final s in spans) {
      final t = s.vAlign == 1
          ? s.text.split('').map((c) => _sup[c] ?? c).join()
          : s.text;
      if (t.trim().isEmpty) {
        b.write(t);
        continue;
      }
      final lead = t.length - t.trimLeft().length;
      final trail = t.length - t.trimRight().length;
      final core = t.trim();
      var m = core;
      if (s.italic) m = '*$m*';
      if (s.bold) m = '**$m**';
      b.write(t.substring(0, lead));
      b.write(m);
      b.write(t.substring(t.length - trail));
    }
    return b.toString();
  }

  @override
  String toString() => plain;
}
