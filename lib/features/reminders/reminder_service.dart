import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../settings/appearance_settings.dart';
import 'reminder_channel.dart';
import 'reminder_scan.dart';

/// What this device has scheduled: notification id → fingerprint. Per
/// device, outside the database. Null from [load] means "unknown".
abstract class ReminderStamps {
  Future<Map<int, String>?> load();
  Future<void> save(Map<int, String> stamps);
}

class MemoryReminderStamps implements ReminderStamps {
  Map<int, String>? stamps;

  @override
  Future<Map<int, String>?> load() async =>
      stamps == null ? null : Map.of(stamps!);
  @override
  Future<void> save(Map<int, String> stamps) async =>
      this.stamps = Map.of(stamps);
}

class PrefsReminderStamps implements ReminderStamps {
  const PrefsReminderStamps();

  static const key = 'reminders.stamps';

  @override
  Future<Map<int, String>?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as String,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<int, String> stamps) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode({for (final e in stamps.entries) '${e.key}': e.value}),
      );
    } catch (_) {}
  }
}

/// At most this many notifications are pending (the earliest win); iOS
/// itself stops at 64.
const maxPendingReminders = 60;

/// Derives this device's notifications from the notes' text: no table, so
/// every device does it for itself after a sync. Schedules what is new or
/// changed, cancels what is gone, passed, checked off or locked.
class ReminderScheduler {
  ReminderScheduler(
    this.db,
    this.channel,
    this.stamps, {
    this.fallbackBody = 'Reminder',
    this.channelName,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final ReminderChannel channel;
  final ReminderStamps stamps;
  final String fallbackBody;
  final String? channelName;
  final DateTime Function() _clock;

  /// Every reminder the notes call for right now, soonest first, capped.
  Future<List<ReminderSpec>> desired() async {
    final now = _clock();
    final rows = await (db.select(
      db.notes,
    )..where((n) => n.content.like('%@{%'))).get();
    final specs = <ReminderSpec>[];
    for (final n in rows) {
      specs.addAll(
        remindersInNote(
          noteId: n.id,
          title: n.title,
          content: n.content,
          now: now,
          emptyBody: fallbackBody,
        ),
      );
    }
    specs.sort((a, b) => a.when.compareTo(b.when));
    return specs.length > maxPendingReminders
        ? specs.sublist(0, maxPendingReminders)
        : specs;
  }

  Future<void> sync() async {
    final want = {for (final s in await desired()) s.id: s};
    final have = await stamps.load() ?? <int, String>{};
    final gone = [
      for (final id in have.keys)
        if (!want.containsKey(id)) id,
    ];
    final fresh = [
      for (final s in want.values)
        if (have[s.id] != s.fingerprint) s,
    ];
    if (gone.isNotEmpty) await channel.cancel(gone);
    if (fresh.isNotEmpty) {
      await channel.schedule([
        for (final s in fresh)
          ReminderRequest(
            id: s.id,
            noteId: s.noteId,
            title: s.title,
            body: s.body,
            when: s.when,
          ),
      ], channelName: channelName);
    }
    await stamps.save({for (final s in want.values) s.id: s.fingerprint});
  }

  /// Cancels everything this device scheduled (the setting turned off).
  Future<void> clear() async {
    await channel.cancelAll();
    await stamps.save({});
  }
}

final reminderStampsProvider = Provider<ReminderStamps>(
  (ref) => const PrefsReminderStamps(),
);

/// How long after startup the first pass waits, and how long writes settle.
final reminderDelaysProvider = Provider<({Duration first, Duration settle})>(
  (ref) =>
      (first: const Duration(seconds: 5), settle: const Duration(seconds: 3)),
);

/// Keeps notifications current while "Reminders" is on, none while off.
/// Inert unless a real [ReminderChannel] is installed. Watched from
/// `PlatformCoordinator`.
final remindersStartupProvider = Provider<void>((ref) {
  final channel = ref.watch(reminderChannelProvider);
  if (!channel.available) return;
  final enabled = ref.watch(
    appearanceSettingsProvider.select((s) => s.reminders),
  );
  final db = ref.watch(databaseProvider);
  final delays = ref.watch(reminderDelaysProvider);
  final stamps = ref.watch(reminderStampsProvider);
  final l10n = deviceL10n();
  final scheduler = ReminderScheduler(
    db,
    channel,
    stamps,
    fallbackBody: l10n.remindersNotificationFallback,
    channelName: l10n.remindersChannelName,
  );

  if (!enabled) {
    stamps.load().then((known) {
      if (known == null || known.isNotEmpty) scheduler.clear();
    });
    return;
  }

  Timer? timer;
  void schedule(Duration after) {
    timer?.cancel();
    timer = Timer(after, () => scheduler.sync().catchError((Object _) {}));
  }

  schedule(delays.first);
  final writes = db
      .tableUpdates(TableUpdateQuery.onTable(db.notes))
      .listen((_) => schedule(delays.settle));
  ref.onDispose(() {
    timer?.cancel();
    writes.cancel();
  });
});

/// Settings → "Reminders" (hidden where notifications aren't available).
class RemindersSettingsTile extends ConsumerWidget {
  const RemindersSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(reminderChannelProvider).available) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(appearanceSettingsProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_none),
      title: Text(context.l10n.remindersSetting),
      subtitle: Text(context.l10n.remindersSettingSubtitle),
      value: settings.reminders,
      onChanged: settings.setReminders,
    );
  }
}
