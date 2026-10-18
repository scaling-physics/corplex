import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/read_aloud/read_aloud_controller.dart';

import 'fake_speaker.dart';

const _pages = {
  1: 'Page one first. Page one second.',
  2: 'Page two first. Page two second.',
  3: 'Page three only.',
};

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSpeaker speaker;

  Future<ReadAloudController> open({int startPage = 1}) async {
    final c = ReadAloudController(
      speaker: speaker,
      pageCount: 3,
      pageText: (p) async => _pages[p]!,
      startPage: startPage,
    );
    addTearDown(c.dispose);
    await c.start();
    await _tick();
    return c;
  }

  setUp(() => speaker = FakeSpeaker());

  test('speaks sentences in order, a few ahead', () async {
    final c = await open();
    expect(c.playing, isTrue);
    expect(speaker.spoken, [
      'Page one first.',
      'Page one second.',
      'Page two first.',
    ]);
    speaker.finishOne();
    await _tick();
    expect(c.index, 1);
    expect(speaker.spoken.last, 'Page two second.');
  });

  test('page follows the speech', () async {
    final c = await open();
    final pages = <int>[];
    c.addListener(() => pages.add(c.page));
    speaker.finishOne();
    await _tick();
    speaker.finishOne();
    await _tick();
    expect(c.page, 2);
    expect(pages, contains(2));
  });

  test('starts from the given page', () async {
    final c = await open(startPage: 2);
    expect(c.page, 2);
    expect(speaker.spoken.first, 'Page two first.');
  });

  test('pause and resume', () async {
    final c = await open();
    await c.pause();
    expect(c.playing, isFalse);
    expect(speaker.pauses, 1);
    await c.resume();
    expect(c.playing, isTrue);
    expect(speaker.resumes, 1);
  });

  test('skip forward and back requeue from the new sentence', () async {
    final c = await open();
    await c.skip(2);
    await _tick();
    expect(c.index, 2);
    expect(speaker.spoken.sublist(speaker.spoken.length - 3), [
      'Page two first.',
      'Page two second.',
      'Page three only.',
    ]);
    expect(c.page, 2);
    await c.skip(-1);
    await _tick();
    expect(c.index, 1);
    expect(speaker.spoken[speaker.spoken.length - 3], 'Page one second.');
    // Skipping past the ends clamps.
    await c.skip(-10);
    expect(c.index, 0);
  });

  test('skip while paused speaks the new sentence on resume', () async {
    final c = await open();
    await c.pause();
    final before = speaker.spoken.length;
    await c.skip(1);
    expect(c.playing, isFalse);
    expect(speaker.spoken.length, before);
    await c.resume();
    await _tick();
    expect(speaker.spoken[before], 'Page one second.');
  });

  test('changing speed requeues at the new rate', () async {
    final c = await open();
    await c.setRate(1.5);
    await _tick();
    expect(c.rate, 1.5);
    expect(speaker.rates.last, 1.5);
    expect(speaker.spoken.last, 'Page two first.');
    await c.setRate(5);
    expect(c.rate, ReadAloudController.maxRate);
    await c.setRate(0.1);
    expect(c.rate, ReadAloudController.minRate);
  });

  test('finishes after the last sentence', () async {
    final c = await open(startPage: 3);
    expect(speaker.spoken, ['Page three only.']);
    speaker.finishOne();
    await _tick();
    expect(c.finished, isTrue);
    expect(c.playing, isFalse);
  });

  test('a page with no text reports empty', () async {
    final c = ReadAloudController(
      speaker: speaker,
      pageCount: 2,
      pageText: (_) async => '',
      startPage: 1,
    );
    addTearDown(c.dispose);
    await c.start();
    expect(c.isEmpty, isTrue);
    expect(speaker.spoken, isEmpty);
  });
}
