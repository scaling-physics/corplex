import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corplex/features/ocr/ocr_engine.dart';
import 'package:corplex/features/voice/voice_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordings are transcribed on iOS and macOS, not Android', () {
    final results = <TargetPlatform, bool>{};
    for (final p in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      final c = ProviderContainer();
      results[p] = c.read(transcribesRecordingsProvider);
      c.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
    expect(results[TargetPlatform.iOS], isTrue);
    expect(results[TargetPlatform.macOS], isTrue);
    expect(results[TargetPlatform.android], isFalse);
  });

  test('dictation is offered on Android only', () {
    final results = <TargetPlatform, bool>{};
    for (final p in [TargetPlatform.macOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = p;
      final c = ProviderContainer();
      results[p] = c.read(dictationOfferedProvider);
      c.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
    expect(results[TargetPlatform.macOS], isFalse);
    expect(results[TargetPlatform.android], isTrue);
  });

  test('macOS microphone settings link', () {
    expect(
      macMicrophoneSettingsUrl,
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
    );
  });

  group('channels', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('corplex/speech'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('corplex/ocr'),
        null,
      );
    });

    Future<Transcript> transcribe(Object? reply) async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('corplex/speech'),
        (call) async => reply,
      );
      return const PlatformTranscriber().transcribeFile('/x.m4a');
    }

    test('speech statuses map', () async {
      final ok = await transcribe({'status': 'ok', 'text': ' hello '});
      expect(ok.status, TranscriptStatus.done);
      expect(ok.text, 'hello');
      expect(
        (await transcribe({'status': 'denied'})).status,
        TranscriptStatus.denied,
      );
      expect(
        (await transcribe({'status': 'unavailable'})).status,
        TranscriptStatus.unavailable,
      );
    });

    test('speech channel error degrades to unavailable', () async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('corplex/speech'),
        (call) async => throw PlatformException(code: 'x'),
      );
      final t = await const PlatformTranscriber().transcribeFile('/x.m4a');
      expect(t.status, TranscriptStatus.unavailable);
    });

    test('ocr result parses lines and words', () async {
      messenger.setMockMethodCallHandler(const MethodChannel('corplex/ocr'), (
        call,
      ) async {
        expect(call.method, 'recognize');
        return [
          {
            'text': 'Hello world',
            'words': [
              {
                'text': 'Hello',
                'left': 0.1,
                'right': 0.4,
                'top': 0.2,
                'bottom': 0.3,
              },
              {
                'text': 'world',
                'left': 0.5,
                'right': 1.2,
                'top': 0.2,
                'bottom': 0.3,
              },
            ],
          },
        ];
      });
      final page = await const PlatformOcrEngine().recognize(Uint8List(0));
      expect(page.text, 'Hello world');
      expect(page.words.last.right, 1.0);
    });
  });
}
