import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'citation_language.dart';
import 'csl_locale.dart';
import 'csl_style.dart';

/// A style the reader added themselves.
class CustomCslStyle {
  const CustomCslStyle(this.name, this.label);
  final String name;
  final String label;
}

/// Loads, parses and remembers CSL styles: the bundled ones from
/// `assets/csl/` and the reader's own from the app-support folder (per
/// device; they are not synced).
class CslRegistry {
  CslRegistry._();

  static final _cache = <String, CslStyle>{};

  /// The XML each cached style was parsed from, so a change of citation
  /// language can re-parse it.
  static final _sources = <String, String>{};

  static final _files = <String, CslLocale>{};
  static final _composed = <String, CslLocale>{};

  static String? _choice;
  static bool _choiceLoaded = false;

  /// Reads a bundled asset. Tests replace this to read from disk.
  static Future<String> Function(String path) loadAsset = rootBundle.loadString;

  /// Reads / writes the saved citation language. Tests replace these.
  static Future<String?> Function() readChoice = CitationLanguageStore.load;
  static Future<void> Function(String?) writeChoice =
      CitationLanguageStore.save;

  /// The app / device language (`de`, `en_GB`) that "Automatic" follows.
  /// Tests replace this.
  static String Function() appLanguage = () =>
      PlatformDispatcher.instance.locale.toLanguageTag();

  /// Where imported styles live. Tests replace this.
  static Future<Directory> Function() customDirectory = () async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'csl_styles'));
  };

  static List<CustomCslStyle> _custom = const [];

  /// Imported styles known so far (see [loadCustom]).
  static List<CustomCslStyle> get custom => _custom;

  /// A style that has been loaded, or null.
  static CslStyle? cached(String name) => _cache[name];

  /// Forgets everything loaded (tests, and after a language change).
  static void debugReset() {
    _cache.clear();
    _sources.clear();
    _files.clear();
    _composed.clear();
    _choice = null;
    _choiceLoaded = false;
  }

  /// The chosen citation language, or null for "Automatic".
  static Future<String?> languageChoice() async {
    if (!_choiceLoaded) {
      _choice = await readChoice();
      _choiceLoaded = true;
    }
    return _choice;
  }

  /// Chooses the citation language ([tag] null = Automatic), saves it and
  /// re-parses the styles already loaded, replacing each only once its new
  /// version is ready so [cached] never goes empty.
  static Future<void> setLanguageChoice(String? tag) async {
    _choice = tag;
    _choiceLoaded = true;
    await writeChoice(tag);
    for (final name in _sources.keys.toList()) {
      try {
        _cache[name] = await _parse(_sources[name]!);
      } catch (_) {
        // Keep the old version.
      }
    }
  }

  /// The tag "Automatic" resolves to for a style with [styleDefault].
  static Future<String> resolvedTag([String? styleDefault]) async =>
      CitationLocales.resolve(
        choice: await languageChoice(),
        styleDefault: styleDefault,
        appLanguage: appLanguage(),
      );

  /// A locale file by tag, read once. Null when it's missing.
  static Future<CslLocale?> _file(String tag) async {
    final hit = _files[tag];
    if (hit != null) return hit;
    try {
      return _files[tag] = CslLocale.parse(
        await loadAsset('assets/csl/locales-$tag.xml'),
        tag: tag,
      );
    } catch (_) {
      return null;
    }
  }

  /// The locale for [tag] with the CSL fallback chain applied: the en-US
  /// file, the language's primary dialect, the exact dialect (each only if
  /// bundled). The style's own `<locale>` blocks are added by
  /// [CslStyle.parse]. Cached per tag.
  static Future<CslLocale> localeFor([String tag = 'en-US']) async {
    final hit = _composed[tag];
    if (hit != null) return hit;
    final files = <CslLocale>[];
    for (final t in CitationLocales.fileChain(tag)) {
      final f = await _file(t);
      if (f != null) files.add(f);
    }
    if (files.isEmpty) throw StateError('No CSL locale could be read');
    var out = CslLocale.compose(files)
        .withoutTerms({'advance-online-publication'});
    // The tag of a locale used for a style is the one asked for, even when
    // only its primary dialect has a file (fr-CA reads fr-FR).
    out = out.overlay(CslLocale.parse('<locale xml:lang="$tag"/>', tag: tag));
    return _composed[tag] = out;
  }

  /// The locale a new style would use now (en-US unless the reader chose
  /// another language or the device speaks one).
  static Future<CslLocale> locale() async => localeFor(await resolvedTag());

  static Future<CslStyle> _parse(String xml) async => CslStyle.parse(
    xml,
    await localeFor(await resolvedTag(CslStyle.defaultLocaleOf(xml))),
  );

  /// Loads bundled style [name] (file `assets/csl/<file>`), or null if it
  /// can't be read.
  static Future<CslStyle?> ensureBundled(String name, String file) async {
    final hit = _cache[name];
    if (hit != null) return hit;
    try {
      final xml = await loadAsset('assets/csl/$file');
      final style = await _parse(xml);
      _sources[name] = xml;
      return _cache[name] = style;
    } catch (_) {
      return null;
    }
  }

  /// Loads an imported style by its [CustomCslStyle.name].
  static Future<CslStyle?> ensureCustom(String name) async {
    final hit = _cache[name];
    if (hit != null) return hit;
    try {
      final dir = await customDirectory();
      final file = File(p.join(dir.path, '$name.csl'));
      if (!file.existsSync()) return null;
      final xml = await file.readAsString();
      final style = await _parse(xml);
      _sources[name] = xml;
      return _cache[name] = style;
    } catch (_) {
      return null;
    }
  }

  /// Finds the styles in the imported folder (skipping broken files).
  static Future<List<CustomCslStyle>> loadCustom() async {
    final found = <CustomCslStyle>[];
    try {
      final dir = await customDirectory();
      if (dir.existsSync()) {
        final files =
            dir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.csl'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          final name = p.basenameWithoutExtension(f.path);
          final style = await ensureCustom(name);
          if (style != null) found.add(CustomCslStyle(name, style.title));
        }
      }
    } catch (_) {}
    return _custom = found;
  }

  static const _maxBytes = 5 * 1024 * 1024;

  /// Validates [xml] and stores it. Throws [CslFormatException] with a
  /// message fit to show.
  static Future<CustomCslStyle> importXml(String xml) async {
    if (xml.length > _maxBytes) {
      throw const CslFormatException(
        'That file is too large to be a style.',
        problem: CslProblem.tooLarge,
      );
    }
    final style = await _parse(xml);
    var slug = style.id
        .split('/')
        .where((s) => s.isNotEmpty)
        .lastOrNull
        ?.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    if (slug == null || slug.isEmpty) {
      slug = style.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    }
    final name = 'user-$slug';
    final dir = await customDirectory();
    dir.createSync(recursive: true);
    await File(p.join(dir.path, '$name.csl')).writeAsString(xml);
    _cache[name] = style;
    _sources[name] = xml;
    final info = CustomCslStyle(name, style.title);
    _custom = [
      for (final c in _custom)
        if (c.name != name) c,
      info,
    ];
    return info;
  }

  /// Reads and imports a `.csl` file.
  static Future<CustomCslStyle> importFile(String path) async {
    final String text;
    try {
      text = await File(path).readAsString();
    } catch (_) {
      throw const CslFormatException(
        'Couldn\'t read that file.',
        problem: CslProblem.unreadable,
      );
    }
    return importXml(text);
  }

  /// Removes an imported style.
  static Future<void> removeCustom(String name) async {
    try {
      final dir = await customDirectory();
      final f = File(p.join(dir.path, '$name.csl'));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _cache.remove(name);
    _sources.remove(name);
    _custom = [
      for (final c in _custom)
        if (c.name != name) c,
    ];
  }
}
