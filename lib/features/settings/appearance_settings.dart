import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How pages look in the PDF reader, independent of the app's theme: a
/// reader often wants a dark page in a light app, or the reverse.
enum ReadingTheme {
  paper('Paper'),
  sepia('Sepia'),
  night('Night');

  const ReadingTheme(this.label);

  final String label;

  /// A color filter over the rendered page (and the marks on it), or null
  /// for the page as printed.
  ColorFilter? get filter => switch (this) {
    ReadingTheme.paper => null,
    ReadingTheme.sepia => _sepia,
    ReadingTheme.night => _night,
  };
}

// The standard sepia tone, slightly lifted so text stays crisp.
const _sepia = ColorFilter.matrix(<double>[
  0.393, 0.769, 0.189, 0, 8, //
  0.349, 0.686, 0.168, 0, 4, //
  0.272, 0.534, 0.131, 0, 0, //
  0, 0, 0, 1, 0, //
]);

// Invert, then rotate the hue back by 180°, so white pages go dark but
// colors (a yellow highlight, a blue figure) keep roughly their hue.
const _night = ColorFilter.matrix(<double>[
  0.574, -1.430, -0.144, 0, 255, //
  -0.426, -0.430, -0.144, 0, 255, //
  -0.426, -1.430, 0.856, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// Per-device appearance preferences (not synced: an iPad in a bright room
/// and a phone in bed want different answers).
class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.reading = ReadingTheme.paper,
  });

  ThemeMode themeMode;
  ReadingTheme reading;

  static const _modeKey = 'appearance.themeMode';
  static const _readingKey = 'appearance.reading';

  static Future<AppearanceSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppearanceSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == prefs.getString(_modeKey),
          orElse: () => ThemeMode.system,
        ),
        reading: ReadingTheme.values.firstWhere(
          (r) => r.name == prefs.getString(_readingKey),
          orElse: () => ReadingTheme.paper,
        ),
      );
    } catch (_) {
      return AppearanceSettings();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _save(_modeKey, mode.name);
  }

  Future<void> setReading(ReadingTheme theme) async {
    reading = theme;
    notifyListeners();
    await _save(_readingKey, theme.name);
  }

  Future<void> _save(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }
}

final appearanceSettingsProvider = ChangeNotifierProvider<AppearanceSettings>(
  (ref) => AppearanceSettings(),
);
