import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  static CslLocale? _locale;

  /// Reads a bundled asset. Tests replace this to read from disk.
  static Future<String> Function(String path) loadAsset = rootBundle.loadString;

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

  static Future<CslLocale> locale() async => _locale ??= CslLocale.parse(
    await loadAsset('assets/csl/locales-en-US.xml'),
  ).withoutTerms({'advance-online-publication'});

  /// Loads bundled style [name] (file `assets/csl/<file>`), or null if it
  /// can't be read.
  static Future<CslStyle?> ensureBundled(String name, String file) async {
    final hit = _cache[name];
    if (hit != null) return hit;
    try {
      final style = CslStyle.parse(
        await loadAsset('assets/csl/$file'),
        await locale(),
      );
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
      final style = CslStyle.parse(await file.readAsString(), await locale());
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
      throw const CslFormatException('That file is too large to be a style.');
    }
    final style = CslStyle.parse(xml, await locale());
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
      throw const CslFormatException('Couldn\'t read that file.');
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
    _custom = [
      for (final c in _custom)
        if (c.name != name) c,
    ];
  }
}
