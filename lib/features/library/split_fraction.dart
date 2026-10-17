import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Share of the split reader's width given to the PDF when nothing has
/// been chosen yet (11 : 9, as the fixed split always was).
const defaultSplitFraction = 0.55;

/// The PDF never gets less than this share of the width...
const minReaderFraction = 0.45;

/// ...and the note never less than this many points.
const minNoteWidth = 320.0;

/// [fraction] limited so the PDF keeps [minReaderFraction] and the note
/// keeps [minNoteWidth] of a [total]-wide split. When the two can't both
/// be had (a very narrow split) the PDF's minimum wins.
double clampSplitFraction(double fraction, double total) {
  if (total <= 0) return defaultSplitFraction;
  final maxFraction = (1 - minNoteWidth / total).clamp(minReaderFraction, 1.0);
  return fraction.clamp(minReaderFraction, maxFraction);
}

/// Where the user dragged the split reader's divider, per device
/// (shared_preferences, not synced). Starts at [defaultSplitFraction] and
/// settles on the saved value once it has loaded.
class SplitFraction extends StateNotifier<double> {
  SplitFraction() : super(defaultSplitFraction) {
    _load();
  }

  static const key = 'splitReaderFraction';

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(key);
      if (saved != null && mounted) state = saved;
    } catch (_) {
      // No storage (a test without a mock): the default stands.
    }
  }

  /// Remembers [fraction] (a drag's end).
  Future<void> save(double fraction) async {
    state = fraction;
    try {
      await (await SharedPreferences.getInstance()).setDouble(key, fraction);
    } catch (_) {}
  }
}

final splitFractionProvider = StateNotifierProvider<SplitFraction, double>(
  (ref) => SplitFraction(),
);

@visibleForTesting
const splitFractionKey = SplitFraction.key;
