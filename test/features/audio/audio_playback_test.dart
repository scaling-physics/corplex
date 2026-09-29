import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/audio/audio_playback.dart';

import '../../support/fake_audio_engine.dart';

Attachment _audio(String id, {String? path = '/x/a.m4a'}) => Attachment(
  id: id,
  type: AttachmentType.podcast,
  path: path,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late FakeAudioEngine engine;
  late AudioPlayback playback;

  setUp(() {
    engine = FakeAudioEngine();
    playback = AudioPlayback(engine);
  });
  tearDown(() => playback.dispose());

  test('open loads the file and starts playing', () async {
    await playback.open(_audio('a1'));
    expect(engine.loads.single.path, '/x/a.m4a');
    expect(engine.isPlaying, isTrue);
    expect(playback.current!.id, 'a1');
  });

  test('re-opening the same recording seeks instead of reloading', () async {
    await playback.open(_audio('a1'));
    await playback.open(_audio('a1'), at: const Duration(minutes: 3));
    expect(engine.loads, hasLength(1));
    expect(engine.seeks.last, const Duration(minutes: 3));
  });

  test('switching recordings reloads and keeps the chosen speed', () async {
    await playback.open(_audio('a1'));
    await playback.cycleSpeed();
    await playback.open(_audio('a2', path: '/x/b.mp3'));
    expect(engine.loads.map((l) => l.path), ['/x/a.m4a', '/x/b.mp3']);
    expect(engine.speed, 1.25);
  });

  test(
    'audio still syncing reports a friendly error without loading',
    () async {
      await playback.open(_audio('a1', path: null));
      expect(engine.loads, isEmpty);
      expect(playback.error, contains("hasn't synced"));
    },
  );

  test(
    'a file the player rejects reports an error, and can be retried',
    () async {
      engine.failLoads = true;
      await playback.open(_audio('a1'));
      expect(playback.error, isNotNull);
      engine.failLoads = false;
      await playback.open(_audio('a1'));
      expect(playback.error, isNull);
      expect(engine.loads, hasLength(1));
    },
  );

  test('seek is clamped to the recording', () async {
    await playback.open(_audio('a1'));
    await Future<void>.delayed(Duration.zero); // duration arrives
    await playback.seek(const Duration(hours: 5));
    await playback.seek(const Duration(seconds: -5));
    expect(engine.seeks, [const Duration(minutes: 30), Duration.zero]);
  });

  test('close stops and hides the player', () async {
    await playback.open(_audio('a1'));
    await playback.close();
    expect(engine.isPlaying, isFalse);
    expect(playback.current, isNull);
  });

  test('play at the end of a recording starts it again', () async {
    await playback.open(_audio('a1'));
    await playback.togglePlay(); // pause
    engine.emitPosition(const Duration(minutes: 30));
    await Future<void>.delayed(Duration.zero);
    engine.seeks.clear();

    await playback.togglePlay();

    expect(engine.seeks, [Duration.zero]);
    expect(engine.isPlaying, isTrue);
  });
}
