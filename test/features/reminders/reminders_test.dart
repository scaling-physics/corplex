import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/lock/note_crypto.dart' show lockedPrefix;
import 'package:corplex/features/notes/date_embed.dart';
import 'package:corplex/features/notes/date_markers.dart';
import 'package:corplex/features/notes/editor_document.dart';
import 'package:corplex/features/projects/calendar.dart';
import 'package:corplex/features/reminders/reminder_channel.dart';
import 'package:corplex/features/reminders/reminder_scan.dart';
import 'package:corplex/features/reminders/reminder_service.dart';
import 'package:corplex/l10n/l10n.dart';

String delta(List<Map<String, Object?>> ops) => jsonEncode(ops);
String text(String t) => delta([
  {'insert': '$t\n'},
]);

class _FakeReminders implements ReminderChannel {
  final scheduled = <int, ReminderRequest>{};
  final cancelled = <int>[];
  var cancelAllCalls = 0;

  @override
  bool get available => true;
  @override
  Future<void> schedule(
    List<ReminderRequest> requests, {
    String? channelName,
  }) async {
    for (final r in requests) {
      scheduled[r.id] = r;
    }
  }

  @override
  Future<void> cancel(List<int> ids) async {
    cancelled.addAll(ids);
    ids.forEach(scheduled.remove);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }

  @override
  Stream<String> get opens => const Stream.empty();
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group('markers', () {
    test('parses with and without a time', () {
      final spans = findDateMentions(
        'Call @{2026-11-14} and @{2026-11-15 09:30}.',
      );
      expect(spans.map((s) => s.mention.raw), [
        '2026-11-14',
        '2026-11-15 09:30',
      ]);
      expect(spans[0].mention.moment, DateTime(2026, 11, 14, 9));
      expect(spans[1].mention.moment, DateTime(2026, 11, 15, 9, 30));
    });

    test('ignores emails, URLs, maths, bad dates and unbalanced text', () {
      expect(findDateMentions('me@{2026-11-14}'), isEmpty);
      expect(findDateMentions('https://x.org/@{2026-11-14}'), isEmpty);
      expect(findDateMentions(r'$a @{2026-11-14} b$'), isEmpty);
      expect(findDateMentions('@{2026-13-40}'), isEmpty);
      expect(findDateMentions('@{2026-02-30}'), isEmpty);
      expect(findDateMentions('@{2026-11-14 25:00}'), isEmpty);
      expect(findDateMentions('@{2026-11-14'), isEmpty);
    });

    test('not inside inline code', () {
      final stored = delta([
        {'insert': 'x '},
        {
          'insert': '@{2026-11-14}',
          'attributes': {'code': true},
        },
        {'insert': '\n'},
      ]);
      expect(dateMentionsToEmbeds(stored), stored);
    });

    test('stored <-> editor round trip beside citations and maths', () {
      final stored = text(
        r'See [@kandel2013] and $x^2$ by @{2026-11-14 09:30} ok',
      );
      final doc = editorDocument(stored);
      final embeds = [
        for (final op in doc.toDelta().toList())
          if (op.data is Map) (op.data as Map).keys.first,
      ];
      expect(embeds, containsAll(['cite', 'date']));
      expect(embeds.where((e) => e == 'date'), hasLength(1));
      final back = storedFromEditor(doc);
      expect(jsonDecode(back), jsonDecode(stored));
      // One character each.
      expect(doc.toPlainText().contains('@{'), isFalse);
    });

    test('labels: today, tomorrow, later, with time; past detection', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final now = DateTime(2026, 11, 12, 10);
      String label(String raw) =>
          dateMentionLabel(l10n, parseDateMention(raw)!, now);
      expect(label('2026-11-12'), 'Today');
      expect(label('2026-11-13'), 'Tomorrow');
      expect(label('2026-11-14'), 'Sat 14 Nov');
      expect(label('2026-11-14 09:30'), 'Sat 14 Nov 09:30');
      expect(label('2027-01-02'), contains('2027'));
      expect(dateMentionPast(parseDateMention('2026-11-11')!, now), isTrue);
      expect(dateMentionPast(parseDateMention('2026-11-12')!, now), isFalse);
      expect(
        dateMentionPast(parseDateMention('2026-11-12 09:00')!, now),
        isTrue,
      );
    });

    test('the @ trigger rules', () {
      expect(dateTriggerAt('@', 0), isTrue);
      expect(dateTriggerAt('hi @', 3), isTrue);
      expect(dateTriggerAt('line\n@', 5), isTrue);
      expect(dateTriggerAt('me@', 2), isFalse);
      expect(dateTriggerAt('and@or', 3), isFalse);
      expect(dateTriggerAt('[@', 1), isFalse);
      expect(dateTriggerAt('@{2026', 0), isFalse);
    });
  });

  group('scan', () {
    final now = DateTime(2026, 11, 1, 12);

    test('future only, body is the paragraph, capped at 120', () {
      final long = 'word ' * 60;
      final specs = remindersInNote(
        noteId: 'n',
        title: 'T',
        content: delta([
          {'insert': 'Submit draft @{2026-11-14}\n'},
          {'insert': 'Old @{2026-10-01}\n'},
          {'insert': '$long @{2026-11-20 08:00}\n'},
        ]),
        now: now,
      );
      expect(specs, hasLength(2));
      expect(specs[0].body, 'Submit draft');
      expect(specs[0].when, DateTime(2026, 11, 14, 9));
      expect(specs[1].body.length, lessThanOrEqualTo(120));
    });

    test('a checked item, code blocks and locked notes give none', () {
      expect(
        remindersInNote(
          noteId: 'n',
          title: 'T',
          content: delta([
            {'insert': 'Do it @{2026-11-14}'},
            {
              'insert': '\n',
              'attributes': {'list': 'checked'},
            },
            {'insert': 'Do it @{2026-11-15}'},
            {
              'insert': '\n',
              'attributes': {'list': 'unchecked'},
            },
          ]),
          now: now,
        ).map((s) => s.when.day),
        [15],
      );
      expect(
        remindersInNote(
          noteId: 'n',
          title: 'T',
          content: '${lockedPrefix}k:@{2026-11-14}',
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('scheduler', () {
    late AppDatabase db;
    late _FakeReminders channel;
    late MemoryReminderStamps stamps;
    late ReminderScheduler scheduler;
    var clock = DateTime(2026, 11, 1, 12);

    Future<void> note(String id, String title, String content) => db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: Value(id),
            title: Value(title),
            content: Value(content),
          ),
        );

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.inMemoryForTesting();
      channel = _FakeReminders();
      stamps = MemoryReminderStamps();
      clock = DateTime(2026, 11, 1, 12);
      scheduler = ReminderScheduler(db, channel, stamps, clock: () => clock);
    });
    tearDown(() => db.close());

    test(
      'schedules once, then diffs: edit, remove, pass, check, lock',
      () async {
        await note('a', 'Alpha', text('Read @{2026-11-14}'));
        await note('b', 'Beta', text('Meet @{2026-11-15 10:00}'));
        await scheduler.sync();
        expect(channel.scheduled, hasLength(2));
        final idA = reminderIdFor('a', '2026-11-14');

        // Nothing changed: nothing sent.
        channel.scheduled.clear();
        await scheduler.sync();
        expect(channel.scheduled, isEmpty);
        expect(channel.cancelled, isEmpty);

        // A title change reschedules just that note's reminder.
        await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
          const NotesCompanion(title: Value('Alpha 2')),
        );
        await scheduler.sync();
        expect(channel.scheduled.keys, [idA]);
        expect(channel.scheduled[idA]!.title, 'Alpha 2');

        // Checked item cancels it.
        await (db.update(db.notes)..where((n) => n.id.equals('a'))).write(
          NotesCompanion(
            content: Value(
              delta([
                {'insert': 'Read @{2026-11-14}'},
                {
                  'insert': '\n',
                  'attributes': {'list': 'checked'},
                },
              ]),
            ),
          ),
        );
        await scheduler.sync();
        expect(channel.cancelled, [idA]);

        // Locking cancels the other.
        await (db.update(db.notes)..where((n) => n.id.equals('b'))).write(
          const NotesCompanion(content: Value('${lockedPrefix}k:zzz')),
        );
        await scheduler.sync();
        expect(channel.cancelled, hasLength(2));
        expect(channel.scheduled, isEmpty);
      },
    );

    test('a passed reminder is cancelled', () async {
      await note('a', 'Alpha', text('Read @{2026-11-14}'));
      await scheduler.sync();
      expect(channel.scheduled, hasLength(1));
      clock = DateTime(2026, 11, 15);
      await scheduler.sync();
      expect(channel.scheduled, isEmpty);
    });

    test('capped at 60, earliest first', () async {
      for (var i = 0; i < 70; i++) {
        final d = DateTime(2026, 12, 1).add(Duration(days: i));
        await note('n$i', 'N$i', text('x @{${dateMentionRaw(d)}}'));
      }
      await scheduler.sync();
      expect(channel.scheduled, hasLength(maxPendingReminders));
      expect(
        channel.scheduled.values
            .map((r) => r.when)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        DateTime(2026, 12, 1).add(const Duration(days: 59, hours: 9)),
      );
    });

    test('clear cancels everything', () async {
      await note('a', 'Alpha', text('Read @{2026-11-14}'));
      await scheduler.sync();
      await scheduler.clear();
      expect(channel.cancelAllCalls, 1);
      expect(await stamps.load(), isEmpty);
    });
  });

  test('calendar marks mentions on their day, once per note', () {
    final items = collectCalendarItems(
      notes: const [],
      papers: const [],
      projects: const [],
      mentions: [
        (
          id: 'n',
          title: 'N',
          content: delta([
            {
              'insert':
                  'a @{2026-11-14}\nb @{2026-11-14 09:00} @{2026-11-16}\n',
            },
          ]),
        ),
      ],
    );
    expect(items['2026-11-14']!.map((i) => i.kind), [CalendarKind.mention]);
    expect(items['2026-11-16']!.single.id, 'n');
  });
}
