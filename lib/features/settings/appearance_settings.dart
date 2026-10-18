import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

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
    ReadingTheme.sepia => const ColorFilter.matrix(_sepiaMatrix),
    ReadingTheme.night => const ColorFilter.matrix(_nightMatrix),
  };

  /// The filter as a 4x5 color matrix (identity for the page as printed),
  /// so switching themes can tween between them.
  List<double> get matrix => switch (this) {
    ReadingTheme.paper => identityColorMatrix,
    ReadingTheme.sepia => _sepiaMatrix,
    ReadingTheme.night => _nightMatrix,
  };
}

const identityColorMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Each of the 20 values of [a] moved fraction [t] of the way to [b].
List<double> lerpColorMatrix(List<double> a, List<double> b, double t) => [
  for (var i = 0; i < 20; i++) a[i] * (1 - t) + b[i] * t,
];

bool _isIdentity(List<double> m) {
  for (var i = 0; i < 20; i++) {
    if ((m[i] - identityColorMatrix[i]).abs() > 1e-6) return false;
  }
  return true;
}

class _MatrixTween extends Tween<List<double>> {
  _MatrixTween({super.end});

  @override
  List<double> lerp(double t) => lerpColorMatrix(begin!, end!, t);
}

/// Applies [theme]'s color filter to [child], easing the matrix from the
/// previous theme's over [AppMotion.medium] when it changes (instantly under
/// reduced motion). [child] is built once, so the page isn't rebuilt per
/// frame; place snapshot boundaries *inside* it so they keep true colors.
class ReadingFilter extends StatelessWidget {
  const ReadingFilter({super.key, required this.theme, required this.child});

  final ReadingTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<List<double>>(
      tween: _MatrixTween(end: theme.matrix),
      duration: AppMotion.of(context, AppMotion.medium),
      curve: AppMotion.standard,
      child: child,
      builder: (context, m, child) {
        final settled = _isIdentity(m);
        return ColorFiltered(
          colorFilter: settled
              ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
              : ColorFilter.matrix(m),
          child: child,
        );
      },
    );
  }
}

// The standard sepia tone, slightly lifted so text stays crisp.
const _sepiaMatrix = <double>[
  0.393, 0.769, 0.189, 0, 8, //
  0.349, 0.686, 0.168, 0, 4, //
  0.272, 0.534, 0.131, 0, 0, //
  0, 0, 0, 1, 0, //
];

// Invert, then rotate the hue back by 180°, so white pages go dark but
// colors (a yellow highlight, a blue figure) keep roughly their hue.
const _nightMatrix = <double>[
  0.574, -1.430, -0.144, 0, 255, //
  -0.426, -0.430, -0.144, 0, 255, //
  -0.426, -1.430, 0.856, 0, 255, //
  0, 0, 0, 1, 0, //
];

/// Per-device appearance preferences (not synced: an iPad in a bright room
/// and a phone in bed want different answers).
class AppearanceSettings extends ChangeNotifier {
  AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.reading = ReadingTheme.paper,
    this.typewriter = false,
    this.interfaceScale = 1.0,
    this.quickNoteHotKey = true,
    this.spellCheck = true,
  });

  ThemeMode themeMode;
  ReadingTheme reading;

  /// Note editor: keep the line being typed at a steady height.
  bool typewriter;

  /// Note editor: underline misspelled words and offer corrections
  /// (macOS and iOS; Android has no checker).
  bool spellCheck;

  /// Desktop: the whole interface's size, as a factor (View → Interface
  /// Size, or Settings). A big low-density display — a 38" 3840×1600
  /// ultrawide at 1× — reads better a step or two up. Applied by
  /// `MacWindowFrame`; one of [interfaceScales].
  double interfaceScale;

  /// Mac: the global ⌃⌥N Quick Note shortcut is registered.
  bool quickNoteHotKey;

  static const interfaceScales = [0.9, 1.0, 1.1, 1.25, 1.4, 1.6];

  static const _modeKey = 'appearance.themeMode';
  static const _readingKey = 'appearance.reading';
  static const _typewriterKey = 'appearance.typewriter';
  static const _spellKey = 'appearance.spellCheck';
  static const _scaleKey = 'appearance.interfaceScale';
  static const _quickNoteKey = 'appearance.quickNoteHotKey';

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
        typewriter: prefs.getBool(_typewriterKey) ?? false,
        interfaceScale: _nearestScale(prefs.getDouble(_scaleKey) ?? 1.0),
        spellCheck: prefs.getBool(_spellKey) ?? true,
        quickNoteHotKey: prefs.getBool(_quickNoteKey) ?? true,
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

  Future<void> setTypewriter(bool on) async {
    typewriter = on;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_typewriterKey, on);
    } catch (_) {}
  }

  Future<void> setQuickNoteHotKey(bool on) async {
    quickNoteHotKey = on;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_quickNoteKey, on);
    } catch (_) {}
  }

  Future<void> setSpellCheck(bool on) async {
    spellCheck = on;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_spellKey, on);
    } catch (_) {}
  }

  Future<void> setInterfaceScale(double scale) async {
    interfaceScale = _nearestScale(scale);
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setDouble(
        _scaleKey,
        interfaceScale,
      );
    } catch (_) {}
  }

  /// One step up (+1) or down (-1) [interfaceScales]; 0 resets to 100%.
  Future<void> stepInterfaceScale(int direction) {
    if (direction == 0) return setInterfaceScale(1.0);
    final i = interfaceScales.indexOf(interfaceScale) + direction;
    return setInterfaceScale(
      interfaceScales[i.clamp(0, interfaceScales.length - 1)],
    );
  }

  static double _nearestScale(double value) => interfaceScales.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );

  Future<void> _save(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }
}

final appearanceSettingsProvider = ChangeNotifierProvider<AppearanceSettings>(
  (ref) => AppearanceSettings(),
);
