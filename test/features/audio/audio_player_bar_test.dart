import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/audio/audio_player_bar.dart';
import 'package:corplex/features/audio/audio_playback.dart';

import '../../support/fake_audio_engine.dart';

Attachment _audio() => Attachment(
  id: 'a1',
  type: AttachmentType.podcast,
  path: '/x/a.m4a',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Widget _host(
  FakeAudioEngine engine, {
  void Function(String, Duration)? onMark,
}) => ProviderScope(
  overrides: [audioEngineProvider.overrideWithValue(engine)],
  child: MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: AudioPlayerBar(onMark: onMark),
    ),
  ),
);

void main() {
  testWidgets('the bar rises in, shows levels only while playing, and leaves', (
    tester,
  ) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(_host(engine));
    expect(find.byType(Slider), findsNothing);

    final playback = ProviderScope.containerOf(
      tester.element(find.byType(AudioPlayerBar)),
    ).read(audioPlaybackProvider);
    await playback.open(_audio());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(AudioPlayerBar),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1), reason: 'mid-rise');

    // Playing: the level bars animate, so the tree never settles.
    expect(find.byKey(const ValueKey('level-bars')), findsOneWidget);
    engine.emitPosition(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    // Bars glide for a moment after an update, then rest: it settles even
    // while playing.
    await tester.pumpAndSettle();
    await playback.togglePlay();
    await tester.pumpAndSettle(); // Settles only once nothing loops.
    expect(find.byKey(const ValueKey('level-bars')), findsNothing);
    expect(fade.opacity.value, 1.0);

    // Closing slides it away, then removes it.
    await playback.close();
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(
      find
          .byType(FadeTransition)
          .evaluate()
          .where(
            (e) =>
                e.widget is FadeTransition &&
                find
                    .descendant(
                      of: find.byType(AudioPlayerBar),
                      matching: find.byWidget(e.widget),
                    )
                    .evaluate()
                    .isNotEmpty,
          ),
      isEmpty,
    );
  });

  testWidgets('reduced motion shows no level bars', (tester) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _host(engine),
      ),
    );
    final playback = ProviderScope.containerOf(
      tester.element(find.byType(AudioPlayerBar)),
    ).read(audioPlaybackProvider);
    await playback.open(_audio());
    await tester.pumpAndSettle();
    expect(playback.playing, isTrue);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byKey(const ValueKey('level-bars')), findsNothing);
  });

  testWidgets('Mark gives a haptic tick', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final engine = FakeAudioEngine();
    final marks = <Duration>[];
    await tester.pumpWidget(_host(engine, onMark: (_, at) => marks.add(at)));
    final playback = ProviderScope.containerOf(
      tester.element(find.byType(AudioPlayerBar)),
    ).read(audioPlaybackProvider);
    await playback.open(_audio());
    await playback.togglePlay(); // Pause so the tree can settle.
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark'));
    await tester.pump();
    expect(marks, hasLength(1));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });
}
