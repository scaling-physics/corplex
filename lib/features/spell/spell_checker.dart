import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A spell checker for the note body. Behind an interface because the real
/// one is a platform channel (macOS `NSSpellChecker`, iOS `UITextChecker`)
/// that doesn't exist under `flutter test` or on Android.
abstract class SpellChecker {
  /// Whether this checker can do anything. False for [InertSpellChecker]
  /// and once a channel turned out to be missing.
  bool get available;

  /// For each text, the misspelled ranges (UTF-16 offsets, which are Dart
  /// string offsets).
  Future<List<List<TextRange>>> check(List<String> texts);

  Future<List<String>> guesses(String word);

  /// Adds [word] to the user's dictionary (shared with other apps).
  Future<void> learn(String word);
}

/// Does nothing: the default (tests, Android). `main()` installs the real
/// one — don't make the default real, the plugin throws under flutter test.
class InertSpellChecker implements SpellChecker {
  const InertSpellChecker();

  @override
  bool get available => false;

  @override
  Future<List<List<TextRange>>> check(List<String> texts) async => [
    for (final _ in texts) const <TextRange>[],
  ];

  @override
  Future<List<String>> guesses(String word) async => const [];

  @override
  Future<void> learn(String word) async {}
}

/// The platform checker over the `corplex/spell` channel. A missing plugin
/// or any platform error means "no spell check": it never throws.
class ChannelSpellChecker implements SpellChecker {
  ChannelSpellChecker([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('corplex/spell');

  final MethodChannel _channel;
  bool _broken = false;

  @override
  bool get available => !_broken;

  Future<T?> _call<T>(String method, Object? args) async {
    if (_broken) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _broken = true;
    } on PlatformException catch (e) {
      debugPrint('spell $method: ${e.message}');
    } catch (_) {}
    return null;
  }

  @override
  Future<List<List<TextRange>>> check(List<String> texts) async {
    final raw = await _call<List<Object?>>('check', {'texts': texts});
    return [
      for (var i = 0; i < texts.length; i++)
        if (raw != null && i < raw.length && raw[i] is List)
          [
            for (final r in raw[i] as List)
              if (r is List && r.length == 2)
                TextRange(
                  start: r[0] as int,
                  end: (r[0] as int) + (r[1] as int),
                ),
          ]
        else
          const <TextRange>[],
    ];
  }

  @override
  Future<List<String>> guesses(String word) async {
    final raw = await _call<List<Object?>>('guesses', {'word': word});
    return [...?raw?.whereType<String>()];
  }

  @override
  Future<void> learn(String word) async {
    await _call<Object?>('learn', {'word': word});
  }
}

final spellCheckerProvider = Provider<SpellChecker>(
  (ref) => const InertSpellChecker(),
);
