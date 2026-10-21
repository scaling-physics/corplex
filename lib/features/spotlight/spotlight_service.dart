import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../settings/appearance_settings.dart';
import 'spotlight_channel.dart';
import 'spotlight_indexer.dart';

final spotlightStampsProvider = Provider<SpotlightStamps>(
  (ref) => const PrefsSpotlightStamps(),
);

/// How long after startup the first pass waits, and how long writes settle
/// before the next (tests shorten both).
final spotlightDelaysProvider = Provider<({Duration first, Duration settle})>(
  (ref) =>
      (first: const Duration(seconds: 5), settle: const Duration(seconds: 3)),
);

/// Keeps Spotlight current while "Show in Spotlight" is on, and empty while
/// it is off. Inert unless a real [SpotlightChannel] is installed. Read
/// (watched) from `PlatformCoordinator`, like `ocrStartupProvider` is from
/// the home shell.
final spotlightStartupProvider = Provider<void>((ref) {
  final channel = ref.watch(spotlightChannelProvider);
  if (!channel.available) return;
  final enabled = ref.watch(
    appearanceSettingsProvider.select((s) => s.spotlight),
  );
  final db = ref.watch(databaseProvider);
  final delays = ref.watch(spotlightDelaysProvider);
  final stamps = ref.watch(spotlightStampsProvider);
  final indexer = SpotlightIndexer(
    db,
    channel,
    stamps,
    untitled: deviceL10n().commonUntitled,
  );

  if (!enabled) {
    // Off clears the index; with nothing recorded there is nothing to clear.
    stamps.load().then((known) {
      if (known == null || known.isNotEmpty) indexer.clear();
    });
    return;
  }

  Timer? timer;
  void schedule(Duration after) {
    timer?.cancel();
    timer = Timer(after, () => indexer.sync().catchError((Object _) {}));
  }

  schedule(delays.first);
  final writes = db
      .tableUpdates(
        TableUpdateQuery.onAllTables([db.notes, db.papers, db.projects]),
      )
      .listen((_) => schedule(delays.settle));
  ref.onDispose(() {
    timer?.cancel();
    writes.cancel();
  });
});

/// Settings → "Show in Spotlight" (macOS only: hidden while no real
/// channel is installed).
class SpotlightSettingsTile extends ConsumerWidget {
  const SpotlightSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(spotlightChannelProvider).available) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(appearanceSettingsProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.manage_search),
      title: Text(context.l10n.spotlightSetting),
      subtitle: Text(context.l10n.spotlightSettingSubtitle),
      value: settings.spotlight,
      onChanged: settings.setSpotlight,
    );
  }
}
