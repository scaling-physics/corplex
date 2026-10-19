import 'package:xml/xml.dart';

import 'csl_locale.dart';

/// Why a `.csl` file can't be used, so the UI can say it in the reader's
/// language (the English [CslFormatException.message] is the fallback).
enum CslProblem {
  notXml,
  notStyle,
  noInfo,
  dependent,
  wrongVersion,
  noLayout,
  noBibliography,
  undefinedMacro,
  noTitle,
  tooLarge,
  unreadable,
}

/// Thrown for a `.csl` file that can't be used. [message] is plain English
/// fit to show; [problem] (with [detail], e.g. the macro name) lets the UI
/// translate it.
class CslFormatException implements Exception {
  const CslFormatException(this.message, {this.problem, this.detail});
  final String message;
  final CslProblem? problem;
  final String? detail;
  @override
  String toString() => message;
}

/// A parsed CSL 1.0.x style.
class CslStyle {
  CslStyle._({
    required this.root,
    required this.title,
    required this.id,
    required this.macros,
    required this.citation,
    required this.bibliography,
    required this.locale,
    required this.numeric,
    required this.hasYearSuffixVariable,
    required this.defaultLocale,
  });

  final XmlElement root;
  final String title;
  final String id;
  final Map<String, XmlElement> macros;
  final XmlElement? citation;
  final XmlElement? bibliography;
  final CslLocale locale;

  /// A citation-number style: the in-text form is a number.
  final bool numeric;

  /// The style prints the year suffix itself (`<text variable="year-suffix">`);
  /// otherwise the processor appends it after the year.
  final bool hasYearSuffixVariable;

  /// The style's `default-locale` (`en-GB`), or null.
  final String? defaultLocale;

  /// The `default-locale` of the style in [xml], or null (also for XML that
  /// can't be read; [parse] reports that properly).
  static String? defaultLocaleOf(String xml) {
    try {
      final v = XmlDocument.parse(xml).rootElement
          .getAttribute('default-locale');
      return v == null || v.trim().isEmpty ? null : v.trim();
    } on XmlException {
      return null;
    }
  }

  /// Parses [xml] against [baseLocale], the composed locale files for the
  /// language to format in; the style's own `<locale>` blocks for that
  /// language are layered on top. Throws [CslFormatException] with a plain-language message
  /// if it isn't a usable independent CSL style.
  factory CslStyle.parse(String xml, CslLocale baseLocale) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException {
      throw const CslFormatException(
        'That file isn\'t valid XML, so it can\'t be a citation style.',
        problem: CslProblem.notXml,
      );
    }
    final root = doc.rootElement;
    if (root.name.local != 'style') {
      throw const CslFormatException(
        'That file isn\'t a citation style (.csl) file.',
        problem: CslProblem.notStyle,
      );
    }
    final children = root.childElements.toList();
    final info = children.where((e) => e.name.local == 'info').firstOrNull;
    if (info == null) {
      throw const CslFormatException(
        'That style has no title or ID block.',
        problem: CslProblem.noInfo,
      );
    }
    final parent = info.childElements.any(
      (e) =>
          e.name.local == 'link' &&
          e.getAttribute('rel') == 'independent-parent',
    );
    if (parent) {
      throw const CslFormatException(
        'This style is a small variant that points to a parent style. '
        'Import the parent style instead.',
        problem: CslProblem.dependent,
      );
    }
    final version = root.getAttribute('version') ?? '';
    if (!version.startsWith('1.')) {
      throw const CslFormatException(
        'Only CSL 1.0 styles are supported.',
        problem: CslProblem.wrongVersion,
      );
    }
    final citation = children
        .where((e) => e.name.local == 'citation')
        .firstOrNull;
    final bibliography = children
        .where((e) => e.name.local == 'bibliography')
        .firstOrNull;
    for (final part in [citation, bibliography].whereType<XmlElement>()) {
      if (!part.childElements.any((e) => e.name.local == 'layout')) {
        throw const CslFormatException(
          'That style is missing its layout, so it can\'t format references.',
          problem: CslProblem.noLayout,
        );
      }
    }
    if (bibliography == null) {
      throw const CslFormatException(
        'That style has no bibliography section, so it can\'t format '
        'reference lists.',
        problem: CslProblem.noBibliography,
      );
    }
    final macros = {
      for (final m in children.where((e) => e.name.local == 'macro'))
        if (m.getAttribute('name') != null) m.getAttribute('name')!: m,
    };
    // Every macro called must exist.
    for (final e in root.descendantElements) {
      final call = e.name.local == 'text' ? e.getAttribute('macro') : null;
      if (call != null && !macros.containsKey(call)) {
        throw CslFormatException(
          'That style uses an undefined macro "$call".',
          problem: CslProblem.undefinedMacro,
          detail: call,
        );
      }
    }
    final title =
        info.childElements
            .where((e) => e.name.local == 'title')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    final id =
        info.childElements
            .where((e) => e.name.local == 'id')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    if (title.isEmpty) {
      throw const CslFormatException(
        'That style has no title.',
        problem: CslProblem.noTitle,
      );
    }
    final locale = baseLocale
        .withOverrides(children.where((e) => e.name.local == 'locale'))
        .withoutTerms({'advance-online-publication'});
    final category = info.childElements.where(
      (e) =>
          e.name.local == 'category' &&
          e.getAttribute('citation-format') != null,
    );
    final numeric = category.any(
      (e) => e.getAttribute('citation-format') == 'numeric',
    );
    return CslStyle._(
      root: root,
      title: title,
      id: id,
      macros: macros,
      citation: citation,
      bibliography: bibliography,
      locale: locale,
      numeric: numeric,
      hasYearSuffixVariable: xml.contains('variable="year-suffix"'),
      defaultLocale: root.getAttribute('default-locale')?.trim(),
    );
  }

  /// Style-level attribute (`initialize-with`, `and` …).
  String? option(String name, {XmlElement? scope}) =>
      scope?.getAttribute(name) ?? root.getAttribute(name);

  XmlElement? get citationLayout => citation?.childElements
      .where((e) => e.name.local == 'layout')
      .firstOrNull;

  XmlElement? get bibliographyLayout => bibliography?.childElements
      .where((e) => e.name.local == 'layout')
      .firstOrNull;
}
