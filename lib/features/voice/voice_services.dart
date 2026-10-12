import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether the microphone (or speech recognition) can be used.
enum MicAccess {
  granted,

  /// The user said no. Only the system Settings can change that now.
  denied,

  /// No recogniser on this device (dictation only).
  unavailable,
}

/// Records a voice note to a file. Behind an interface so tests don't need
/// the plugin.
abstract class VoiceRecorder {
  Future<MicAccess> ensureAccess();

  /// Starts recording into app storage.
  Future<void> start();

  /// Input level, 0..1, while recording.
  Stream<double> get levels;

  /// Stops and returns the file's path.
  Future<String?> stop();

  /// Stops and deletes what was recorded.
  Future<void> cancel();

  Future<void> dispose();
}

/// How the transcription of a finished recording went.
enum TranscriptStatus {
  /// [Transcript.text] is the transcript (possibly empty: no speech heard).
  done,

  /// This device can't transcribe (no model for the language, or the
  /// platform has no on-device file transcription). The audio is kept.
  unavailable,

  /// Speech Recognition permission was refused.
  denied,
}

class Transcript {
  const Transcript(this.status, [this.text = '']);
  final TranscriptStatus status;
  final String text;
}

/// Turns a recording into text, entirely on the device.
abstract class Transcriber {
  Future<Transcript> transcribeFile(String path);
}

/// Live dictation: text only, no audio kept. Used where a recording can't be
/// transcribed afterwards (Android).
abstract class Dictation {
  Future<MicAccess> ensureAccess();

  /// Starts listening; [onText] gets the whole text so far on every change.
  Future<void> start(void Function(String text) onText);

  Stream<double> get levels;

  /// Stops and returns the final text.
  Future<String> stop();

  Future<void> cancel();

  Future<void> dispose();
}

final voiceRecorderProvider = Provider.autoDispose<VoiceRecorder>((ref) {
  final recorder = PluginVoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final transcriberProvider = Provider<Transcriber>(
  (ref) => const PlatformTranscriber(),
);

final dictationProvider = Provider.autoDispose<Dictation>((ref) {
  final dictation = SpeechDictation();
  ref.onDispose(dictation.dispose);
  return dictation;
});

/// Whether "Dictate" is offered next to "Voice note": only where a recording
/// can't be transcribed, so the user can still get speech into text.
final dictationOfferedProvider = Provider<bool>(
  (ref) => defaultTargetPlatform == TargetPlatform.android,
);

/// Opens this app's page in the system Settings.
final openAppSettingsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await const AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.corplex.corplex',
      ).launch();
    } else {
      await launchUrl(Uri.parse('app-settings:'));
    }
  },
);

/// Level in dB (about -60 silence .. 0 loud) to 0..1.
double levelFromDb(double db) => ((db + 50) / 50).clamp(0.0, 1.0);

/// `record`: AAC in an .m4a, mono, straight into the attachments folder so
/// the file never needs copying.
class PluginVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<MicAccess> ensureAccess() async =>
      await _recorder.hasPermission() ? MicAccess.granted : MicAccess.denied;

  @override
  Future<void> start() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'attachments'));
    await dir.create(recursive: true);
    _path = p.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch}_voice_note.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        sampleRate: 22050,
        bitRate: 48000,
      ),
      path: _path!,
    );
  }

  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 80))
      .map((a) => levelFromDb(a.current));

  @override
  Future<String?> stop() async => await _recorder.stop() ?? _path;

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _path;
    if (path != null) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// On-device file transcription through the `corplex/speech` channel
/// (`SceneDelegate.swift`: `SFSpeechURLRecognitionRequest` with
/// `requiresOnDeviceRecognition`). Other platforms have no such API.
class PlatformTranscriber implements Transcriber {
  const PlatformTranscriber();

  static const _channel = MethodChannel('corplex/speech');

  @override
  Future<Transcript> transcribeFile(String path) async {
    try {
      final reply = await _channel.invokeMapMethod<String, String>(
        'transcribe',
        {'path': path},
      );
      final text = reply?['text'] ?? '';
      return switch (reply?['status']) {
        'ok' => Transcript(TranscriptStatus.done, text.trim()),
        'denied' => const Transcript(TranscriptStatus.denied),
        _ => const Transcript(TranscriptStatus.unavailable),
      };
    } on MissingPluginException {
      return const Transcript(TranscriptStatus.unavailable);
    } on PlatformException {
      return const Transcript(TranscriptStatus.unavailable);
    }
  }
}

/// `speech_to_text`, preferring on-device recognition. Restarts itself when
/// the system recogniser stops after a pause, so a long thought isn't cut.
class SpeechDictation implements Dictation {
  final SpeechToText _speech = SpeechToText();
  final _levels = StreamController<double>.broadcast();
  var _committed = '';
  var _current = '';
  var _running = false;
  void Function(String text)? _onText;

  String get _text =>
      [_committed, _current].where((s) => s.isNotEmpty).join(' ');

  @override
  Future<MicAccess> ensureAccess() async {
    final ok = await _speech.initialize(
      onStatus: (status) {
        if (_running && status == 'done') {
          _commit();
          _listen();
        }
      },
      onError: (_) {},
    );
    if (ok) return MicAccess.granted;
    return await _speech.hasPermission
        ? MicAccess.unavailable
        : MicAccess.denied;
  }

  void _commit() {
    _committed = _text;
    _current = '';
  }

  Future<void> _listen() => _speech.listen(
    onResult: (r) {
      _current = r.recognizedWords;
      _onText?.call(_text);
    },
    onSoundLevelChange: (db) {
      if (!_levels.isClosed) _levels.add(((db + 2) / 12).clamp(0.0, 1.0));
    },
    listenOptions: SpeechListenOptions(
      onDevice: true,
      partialResults: true,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 6),
      listenMode: ListenMode.dictation,
    ),
  );

  @override
  Future<void> start(void Function(String text) onText) async {
    _onText = onText;
    _committed = '';
    _current = '';
    _running = true;
    await _listen();
  }

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<String> stop() async {
    _running = false;
    await _speech.stop();
    return _text;
  }

  @override
  Future<void> cancel() async {
    _running = false;
    await _speech.cancel();
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _levels.close();
    await _speech.cancel();
  }
}
