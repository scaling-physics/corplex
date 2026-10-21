import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A problem the checker found. Most are misspellings; on macOS it also
/// reports grammar ([grammar], with the checker's [message] and its
/// [corrections]), which can span several words.
class SpellIssue extends TextRange {
  const SpellIssue({
    required super.start,
    required super.end,
    this.grammar = false,
    this.message,
    this.corrections = const [],
  });

  final bool grammar;
  final String? message;
  final List<String> corrections;
}

/// A spell checker for the note body. Behind an interface because the real
/// one is a platform channel (macOS `NSSpellChecker`, iOS `UITextChecker`)
/// that doesn't exist under `flutter test` or on Android.
abstract class SpellChecker {
  /// Whether this checker can do anything. False for [InertSpellChecker]
  /// and once a channel turned out to be missing.
  bool get available;

  /// For each text, the misspelled ranges (UTF-16 offsets, which are Dart
  /// string offsets). A range may be a [SpellIssue] with more detail.
  Future<List<List<TextRange>>> check(List<String> texts);

  /// Suggestions for [word], best first. [text] is the paragraph it sits in
  /// and [start] its offset there: the checker ranks by context and picks
  /// the paragraph's language.
  Future<List<String>> guesses(String word, {String? text, int? start});

  /// Adds [word] to the user's dictionary (shared with other apps).
  Future<void> learn(String word);

  /// Stops flagging [word] until the app quits (every note, like macOS's
  /// Ignore Spelling).
  Future<void> ignore(String word);
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
  Future<List<String>> guesses(String word, {String? text, int? start}) async =>
      const [];

  @override
  Future<void> learn(String word) async {}

  @override
  Future<void> ignore(String word) async {}
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
              if (r is List && r.length >= 2 && r[0] is int && r[1] is int)
                SpellIssue(
                  start: r[0] as int,
                  end: (r[0] as int) + (r[1] as int),
                  // [start, length, 1, message, [corrections]] is grammar.
                  grammar: r.length >= 3 && r[2] == 1,
                  message: r.length >= 4 && r[3] is String
                      ? r[3] as String
                      : null,
                  corrections: r.length >= 5 && r[4] is List
                      ? (r[4] as List).whereType<String>().toList()
                      : const [],
                ),
          ]
        else
          const <TextRange>[],
    ];
  }

  @override
  Future<List<String>> guesses(String word, {String? text, int? start}) async {
    final raw = await _call<List<Object?>>('guesses', {
      'word': word,
      if (text != null && start != null) ...{'text': text, 'start': start},
    });
    return [...?raw?.whereType<String>()];
  }

  @override
  Future<void> learn(String word) async {
    await _call<Object?>('learn', {'word': word});
  }

  @override
  Future<void> ignore(String word) async {
    await _call<Object?>('ignore', {'word': word});
  }
}

final spellCheckerProvider = Provider<SpellChecker>(
  (ref) => const InertSpellChecker(),
);
