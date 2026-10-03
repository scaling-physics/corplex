import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../data/database.dart';
import 'audio_link.dart';

/// The few player operations the app needs, so tests can run without the
/// just_audio platform plugin.
abstract class AudioEngine {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;

  /// Loads a recording. [title] is what the lock screen and the
  /// notification show while it plays.
  Future<void> load({String? path, String? url, String title = ''});
  Future<void> play();
  Future<void> pause();

  /// Stops and lets go of the recording (and its notification).
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  final _player = AudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  // just_audio keeps `playing` true after a track ends (it's "playing"
  // silence in the completed state); the app wants "is sound coming out".
  @override
  Stream<bool> get playingStream => _player.playerStateStream
      .map((s) => s.playing && s.processingState != ProcessingState.completed)
      .distinct();

  /// Call once before the first player is made (from `main`): playback
  /// then carries on in the background with lock-screen and notification
  /// controls.
  static Future<void> initBackground() => JustAudioBackground.init(
    androidNotificationChannelId: 'com.corplex.corplex.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationIcon: 'drawable/ic_stat_corplex',
    androidNotificationOngoing: true,
  );

  @override
  Future<void> load({String? path, String? url, String title = ''}) async {
    final tag = MediaItem(
      id: path ?? url!,
      title: title.isEmpty ? 'Recording' : title,
      album: 'Corplex',
    );
    if (path != null) {
      await _player.setFilePath(path, tag: tag);
    } else {
      await _player.setUrl(url!, tag: tag);
    }
  }

  // just_audio's play() completes only when playback *stops*; callers here
  // just want it started.
  @override
  Future<void> play() async => unawaited(_player.play());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}

/// App-wide "what's playing": one recording at a time, shared by every
/// screen, so a podcast started from a paper keeps playing (and can be
/// timestamped) while you write in a note.
class AudioPlayback extends ChangeNotifier {
  AudioPlayback(this._engine) {
    _subs = [
      _engine.positionStream.listen((p) {
        _position = p;
        notifyListeners();
      }),
      _engine.durationStream.listen((d) {
        _duration = d;
        notifyListeners();
      }),
      _engine.playingStream.listen((playing) {
        _playing = playing;
        notifyListeners();
      }),
    ];
  }

  static const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];

  final AudioEngine _engine;
  late final List<StreamSubscription<Object?>> _subs;

  Attachment? _current;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  double _speed = 1;
  String? _error;

  Attachment? get current => _current;
  Duration get position => _position;
  Duration? get duration => _duration;
  bool get playing => _playing;
  double get speed => _speed;

  /// Why the last [open] failed, for the player bar to show.
  String? get error => _error;

  /// Starts [attachment] (optionally from [at]). Re-opening what's already
  /// loaded just seeks, so tapping timestamps in a row doesn't reload.
  Future<void> open(Attachment attachment, {Duration? at}) async {
    final source = audioSourceOf(attachment);
    if (source == null) {
      _error = 'This recording hasn\'t synced to this device yet.';
      _current = attachment;
      notifyListeners();
      return;
    }
    try {
      if (_current?.id != attachment.id || _error != null) {
        _current = attachment;
        _error = null;
        _position = Duration.zero;
        _duration = null;
        notifyListeners();
        await _engine.load(
          path: source.path,
          url: source.url,
          title: attachment.title ?? attachment.path?.split('/').last ?? '',
        );
        await _engine.setSpeed(_speed);
      }
      if (at != null) await _engine.seek(at);
      await _engine.play();
    } catch (_) {
      _error = 'Couldn\'t play this recording.';
      notifyListeners();
    }
  }

  /// Pause, resume, or — at the end of the recording — play it again.
  Future<void> togglePlay() async {
    if (_playing) return _engine.pause();
    final duration = _duration;
    if (duration != null &&
        _position >= duration - const Duration(milliseconds: 300)) {
      await _engine.seek(Duration.zero);
    }
    await _engine.play();
  }

  Future<void> seek(Duration to) {
    final max = _duration;
    var target = to < Duration.zero ? Duration.zero : to;
    if (max != null && target > max) target = max;
    return _engine.seek(target);
  }

  Future<void> skip(Duration by) => seek(_position + by);

  /// Steps through [speeds].
  Future<void> cycleSpeed() {
    _speed = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    notifyListeners();
    return _engine.setSpeed(_speed);
  }

  /// Stops and hides the player.
  Future<void> close() async {
    await _engine.stop();
    _current = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _engine.dispose();
    super.dispose();
  }
}

final audioEngineProvider = Provider<AudioEngine>((ref) => JustAudioEngine());

final audioPlaybackProvider = ChangeNotifierProvider<AudioPlayback>(
  (ref) => AudioPlayback(ref.watch(audioEngineProvider)),
);
