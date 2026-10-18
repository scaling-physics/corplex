import 'dart:async';

import 'package:corplex/features/read_aloud/speaker.dart';

/// Completes utterances on demand.
class FakeSpeaker implements Speaker {
  final spoken = <String>[];
  final rates = <double>[];
  final _open = <Completer<bool>>[];
  int pauses = 0;
  int resumes = 0;
  int stops = 0;

  @override
  bool get available => true;

  /// Utterances handed over and not yet finished.
  int get queued => _open.length;

  @override
  Future<bool> speak(String text, {required double rate, String? language}) {
    spoken.add(text);
    rates.add(rate);
    final c = Completer<bool>();
    _open.add(c);
    return c.future;
  }

  /// Finishes the oldest queued utterance.
  void finishOne() => _open.removeAt(0).complete(true);

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> stop() async {
    stops++;
    final open = List.of(_open);
    _open.clear();
    for (final c in open) {
      c.complete(false);
    }
  }
}
