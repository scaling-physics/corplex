import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text to speech, behind an interface because the real one is a platform
/// channel (`corplex/speak`) that doesn't exist under `flutter test`.
///
/// Utterances queue: calling [speak] again while one is being spoken adds
/// to the end, and each call's future completes when its own utterance has
/// been spoken (true) or was cut off by [stop] or an error (false).
abstract class Speaker {
  /// False for the inert default and once the channel turned out missing.
  bool get available;

  /// [rate] is a multiplier of the normal speaking speed (1 = normal).
  /// [language] is a BCP-47 tag like `en` or `de-DE`; null = the system's.
  Future<bool> speak(String text, {required double rate, String? language});

  Future<void> pause();
  Future<void> resume();

  /// Cuts off the current utterance and drops everything queued.
  Future<void> stop();
}

/// Does nothing: the default (tests). `main()` installs the real one —
/// don't make the default real, the channel is missing under flutter test.
class InertSpeaker implements Speaker {
  const InertSpeaker();

  @override
  bool get available => false;

  @override
  Future<bool> speak(
    String text, {
    required double rate,
    String? language,
  }) async => false;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}

/// The platform speaker over `corplex/speak` (AVSpeechSynthesizer on iOS and
/// macOS, `TextToSpeech` on Android). Never throws: any platform error
/// means the utterance wasn't spoken.
class ChannelSpeaker implements Speaker {
  ChannelSpeaker([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('corplex/speak') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _pending = <int, Completer<bool>>{};
  int _nextId = 1;
  bool _broken = false;

  @override
  bool get available => !_broken;

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'done') return null;
    final args = call.arguments as Map<Object?, Object?>;
    final id = (args['id'] as num).toInt();
    _pending.remove(id)?.complete(args['finished'] == true);
    return null;
  }

  @override
  Future<bool> speak(
    String text, {
    required double rate,
    String? language,
  }) async {
    if (_broken) return false;
    final id = _nextId++;
    final done = _pending[id] = Completer<bool>();
    try {
      await _channel.invokeMethod<void>('speak', {
        'id': id,
        'text': text,
        'rate': rate,
        'language': language,
      });
    } on MissingPluginException {
      _broken = true;
      _pending.remove(id);
      return false;
    } on PlatformException catch (e) {
      debugPrint('speak: ${e.message}');
      _pending.remove(id);
      return false;
    }
    return done.future;
  }

  Future<void> _simple(String method) async {
    if (_broken) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      _broken = true;
    } catch (_) {}
  }

  @override
  Future<void> pause() => _simple('pause');

  @override
  Future<void> resume() => _simple('resume');

  @override
  Future<void> stop() async {
    await _simple('stop');
    // Native reports each cut-off utterance too; this makes sure nobody
    // waits on one that never reports.
    final stale = _pending.values.toList();
    _pending.clear();
    for (final c in stale) {
      if (!c.isCompleted) c.complete(false);
    }
  }
}

/// The app-wide speaker; the inert one unless `main()` overrides it.
final speakerProvider = Provider<Speaker>((ref) => const InertSpeaker());
