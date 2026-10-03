import 'dart:async';

import 'package:corplex/features/audio/audio_playback.dart';

/// Records what the app asked the player to do, and echoes state back
/// through the streams like a real player would.
class FakeAudioEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  final loads = <({String? path, String? url, String title})>[];
  final seeks = <Duration>[];
  double speed = 1;
  bool isPlaying = false;
  bool failLoads = false;
  Duration fakeDuration = const Duration(minutes: 30);

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  /// Simulates playback reaching [p].
  void emitPosition(Duration p) => _position.add(p);

  @override
  Future<void> load({String? path, String? url, String title = ''}) async {
    if (failLoads) throw Exception('unsupported');
    loads.add((path: path, url: url, title: title));
    _duration.add(fakeDuration);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playing.add(false);
  }

  bool stopped = false;

  @override
  Future<void> stop() async {
    stopped = true;
    isPlaying = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
  }
}
