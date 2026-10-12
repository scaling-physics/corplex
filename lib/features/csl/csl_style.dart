import 'package:xml/xml.dart';

import 'csl_locale.dart';

/// Thrown for a `.csl` file that can't be used. [message] is meant to be
/// shown to the reader as is.
class CslFormatException implements Exception {
  const CslFormatException(this.message);
  final String message;
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

  /// Parses [xml]. Throws [CslFormatException] with a plain-language message
  /// if it isn't a usable independent CSL style.
  factory CslStyle.parse(String xml, CslLocale baseLocale) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException {
      throw const CslFormatException(
        'That file isn\'t valid XML, so it can\'t be a citation style.',
      );
    }
    final root = doc.rootElement;
    if (root.name.local != 'style') {
      throw const CslFormatException(
        'That file isn\'t a citation style (.csl) file.',
      );
    }
    final children = root.childElements.toList();
    final info = children.where((e) => e.name.local == 'info').firstOrNull;
    if (info == null) {
      throw const CslFormatException('That style has no title or ID block.');
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
      );
    }
    final version = root.getAttribute('version') ?? '';
    if (!version.startsWith('1.')) {
      throw const CslFormatException('Only CSL 1.0 styles are supported.');
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
        );
      }
    }
    if (bibliography == null) {
      throw const CslFormatException(
        'That style has no bibliography section, so it can\'t format '
        'reference lists.',
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
        throw CslFormatException('That style uses an undefined macro "$call".');
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
      throw const CslFormatException('That style has no title.');
    }
    final locale = baseLocale
        .withOverrides(
          children.where((e) => e.name.local == 'locale').where((e) {
            final lang = e.getAttribute(
              'lang',
              namespaceUri: 'http://www.w3.org/XML/1998/namespace',
            );
            return lang == null || lang.startsWith('en');
          }),
        )
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
