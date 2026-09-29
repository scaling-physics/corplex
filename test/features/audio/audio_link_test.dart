import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/data/tables/attachments_table.dart';
import 'package:corplex/features/audio/audio_link.dart';

Attachment _attachment({
  AttachmentType type = AttachmentType.podcast,
  String? path,
  String? url,
  String? storageKey,
}) => Attachment(
  id: 'a1',
  type: type,
  path: path,
  url: url,
  storageKey: storageKey,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('timestamp links', () {
    test('round-trip', () {
      final link = audioTimestampLink(
        'abc-123',
        const Duration(minutes: 12, seconds: 34),
      );
      expect(link, 'corplex://audio/abc-123?t=754');
      final parsed = parseAudioTimestampLink(link)!;
      expect(parsed.attachmentId, 'abc-123');
      expect(parsed.at, const Duration(seconds: 754));
    });

    test('ordinary and malformed links are not timestamps', () {
      for (final link in [
        'https://notebooklm.google.com/notebook/x',
        'corplex://note/abc?t=1',
        'corplex://audio/?t=5',
        'corplex://audio/abc?t=-3',
        'corplex://audio/abc?t=soon',
        'not a link',
      ]) {
        expect(parseAudioTimestampLink(link), isNull, reason: link);
      }
    });

    test('format', () {
      expect(formatTimestamp(Duration.zero), '0:00');
      expect(formatTimestamp(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(
        formatTimestamp(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('audioSourceOf', () {
    test('a local podcast file plays from the file', () {
      final s = audioSourceOf(_attachment(path: '/x/overview.m4a'))!;
      expect(s.path, '/x/overview.m4a');
      expect(s.url, isNull);
    });

    test('an audio-looking generic file plays too', () {
      expect(
        audioSourceOf(
          _attachment(type: AttachmentType.file, path: '/x/lecture.MP3'),
        ),
        isNotNull,
      );
      expect(
        audioSourceOf(
          _attachment(type: AttachmentType.file, path: '/x/notes.pdf'),
        ),
        isNull,
      );
    });

    test('direct audio URLs stream; share pages do not', () {
      expect(
        audioSourceOf(
          _attachment(url: 'https://cdn.example.com/ep1.mp3?sig=1'),
        )!.url,
        isNotNull,
      );
      expect(
        audioSourceOf(
          _attachment(url: 'https://notebooklm.google.com/notebook/abc'),
        ),
        isNull,
      );
    });

    test(
      'synced audio not yet downloaded is still audio, just not playable',
      () {
        final a = _attachment(storageKey: 'u/attachments/a1.m4a');
        expect(audioSourceOf(a), isNull);
        expect(isAudioAttachment(a), isTrue);
      },
    );
  });
}
