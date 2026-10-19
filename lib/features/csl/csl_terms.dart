import '../library/citation_formatter.dart';
import 'csl_registry.dart';

/// A locale term (`figure`, `table`, `et-al`, `month-03` …) in the language
/// [style] formats in, or null when the style isn't a loadable CSL style or
/// the locale has no such term. Loads the style first, so it speaks the
/// reader's citation language (see `CitationLocales`).
Future<String?> cslTerm(
  CitationStyle style,
  String name, {
  String form = 'long',
  bool plural = false,
}) async {
  final csl = await style.ensureLoaded();
  final t = csl?.locale.term(name, form: form, plural: plural);
  return t == null || t.isEmpty ? null : t;
}

/// The same without a style: the term in the locale the reader's citation
/// language resolves to ("Automatic" follows the device; a style's
/// `default-locale` can't apply without a style).
Future<String?> cslLocaleTerm(
  String name, {
  String form = 'long',
  bool plural = false,
}) async {
  final t = (await CslRegistry.locale()).term(name, form: form, plural: plural);
  return t == null || t.isEmpty ? null : t;
}

/// A bibliography heading in [style]'s language, or null. CSL locales have
/// no "Bibliography" term; the closest is the plural of `reference`
/// ("References", "Referenzen", "Références"), capitalised.
Future<String?> cslBibliographyHeading(CitationStyle style) async {
  final t = await cslTerm(style, 'reference', plural: true);
  if (t == null) return null;
  return t[0].toUpperCase() + t.substring(1);
}
