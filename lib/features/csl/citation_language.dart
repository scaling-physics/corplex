import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'csl_registry.dart';

/// A CSL locale Corplex ships (`assets/csl/locales-<tag>.xml`).
class CitationLocaleInfo {
  const CitationLocaleInfo(this.tag, this.label);

  /// The CSL tag, `de-AT`.
  final String tag;

  /// The language's name in itself, which is how a language picker reads
  /// best ("Deutsch", not "German").
  final String label;
}

/// The bundled locales and how a citation language is chosen.
abstract final class CitationLocales {
  static const bundled = <CitationLocaleInfo>[
    CitationLocaleInfo('en-US', 'English US'),
    CitationLocaleInfo('en-GB', 'English UK'),
    CitationLocaleInfo('de-DE', 'Deutsch (Deutschland)'),
    CitationLocaleInfo('de-AT', 'Deutsch (Österreich)'),
    CitationLocaleInfo('fr-FR', 'Français'),
    CitationLocaleInfo('es-ES', 'Español'),
    CitationLocaleInfo('it-IT', 'Italiano'),
    CitationLocaleInfo('nl-NL', 'Nederlands'),
    CitationLocaleInfo('pt-BR', 'Português (Brasil)'),
  ];

  /// The locale file CSL falls back to for a bare language.
  static const _primary = {
    'en': 'en-US',
    'de': 'de-DE',
    'fr': 'fr-FR',
    'es': 'es-ES',
    'it': 'it-IT',
    'nl': 'nl-NL',
    'pt': 'pt-BR',
  };

  static bool isBundled(String tag) => bundled.any((l) => l.tag == tag);

  static String _norm(String tag) {
    final parts = tag.split(RegExp(r'[-_]'));
    if (parts.length == 1) return parts.first.toLowerCase();
    return '${parts.first.toLowerCase()}-${parts[1].toUpperCase()}';
  }

  /// The locale files to read for [tag], most general first, ending in the
  /// exact dialect: `de-AT` -> `[en-US, de-DE, de-AT]`; an unknown `fr-CA`
  /// -> `[en-US, fr-FR]`; an unknown language -> `[en-US]`.
  static List<String> fileChain(String tag) {
    final t = _norm(tag);
    final lang = t.split('-').first;
    final out = <String>['en-US'];
    final primary = _primary[lang];
    if (primary != null && !out.contains(primary)) out.add(primary);
    if (isBundled(t) && !out.contains(t)) out.add(t);
    return out;
  }

  /// The label for [tag] (the closest bundled locale for an unbundled one).
  static String labelFor(String tag) {
    final t = _norm(tag);
    for (final l in bundled) {
      if (l.tag == t) return l.label;
    }
    final p = _primary[t.split('-').first];
    for (final l in bundled) {
      if (l.tag == p) return l.label;
    }
    return 'English US';
  }

  /// The language to format in. An explicit [choice] wins; "Automatic"
  /// (null) uses the style's `default-locale` ([styleDefault]) if it has
  /// one, else the app/device language ([appLanguage], `de` or `de_AT`)
  /// when a bundled locale speaks it, else `en-US`.
  static String resolve({
    String? choice,
    String? styleDefault,
    String? appLanguage,
  }) {
    if (choice != null && choice.isNotEmpty) return _norm(choice);
    if (styleDefault != null && styleDefault.isNotEmpty) {
      return _norm(styleDefault);
    }
    if (appLanguage != null && appLanguage.isNotEmpty) {
      final t = _norm(appLanguage);
      if (isBundled(t)) return t;
      final p = _primary[t.split('-').first];
      if (p != null) return p;
    }
    return 'en-US';
  }
}

const _prefsKey = 'csl.citationLanguage';

/// The per-device citation language, kept in shared_preferences (never
/// synced). Null is "Automatic".
abstract final class CitationLanguageStore {
  static Future<String?> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_prefsKey);
      return v == null || v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? tag) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (tag == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, tag);
      }
    } catch (_) {}
  }
}

/// The chosen citation language (null = Automatic). Setting it saves it and
/// reloads the styles that are already loaded.
final citationLanguageProvider =
    AsyncNotifierProvider<CitationLanguageController, String?>(
      CitationLanguageController.new,
    );

class CitationLanguageController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => CslRegistry.languageChoice();

  Future<void> choose(String? tag) async {
    await CslRegistry.setLanguageChoice(tag);
    state = AsyncData(tag);
  }
}
