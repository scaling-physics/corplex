import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../library/all_highlights_screen.dart';

/// Days until a highlight comes back after each successive "Keep".
const reviewIntervals = [1, 3, 7, 14, 30, 90];

/// Where one highlight is in its review schedule.
class ReviewEntry {
  const ReviewEntry({required this.keeps, required this.due});

  /// How many times it has been kept.
  final int keeps;
  final DateTime due;

  Map<String, Object> toJson() => {'k': keeps, 'd': due.millisecondsSinceEpoch};
}

/// The next due date after keeping [entry] (null: never reviewed) at [now].
ReviewEntry keepEntry(ReviewEntry? entry, DateTime now) {
  final keeps = entry?.keeps ?? 0;
  final days = reviewIntervals[keeps.clamp(0, reviewIntervals.length - 1)];
  return ReviewEntry(
    keeps: keeps + 1,
    due: now.add(Duration(days: days)),
  );
}

/// Skipping asks again tomorrow, without counting as a review.
ReviewEntry skipEntry(ReviewEntry? entry, DateTime now) => ReviewEntry(
  keeps: entry?.keeps ?? 0,
  due: now.add(const Duration(days: 1)),
);

/// When [highlight] is next due: its schedule, or a day after it was made.
DateTime dueDateOf(Highlight highlight, Map<String, ReviewEntry> schedule) =>
    schedule[highlight.id]?.due ??
    highlight.createdAt.add(const Duration(days: 1));

/// The highlights due at [now], most overdue first.
List<HighlightWithPaper> dueHighlights(
  List<HighlightWithPaper> all,
  Map<String, ReviewEntry> schedule,
  DateTime now,
) {
  final due = [
    for (final e in all)
      if (!dueDateOf(e.highlight, schedule).isAfter(now)) e,
  ];
  due.sort(
    (a, b) => dueDateOf(
      a.highlight,
      schedule,
    ).compareTo(dueDateOf(b.highlight, schedule)),
  );
  return due;
}

/// [schedule] without entries for highlights that no longer exist.
Map<String, ReviewEntry> pruneSchedule(
  Map<String, ReviewEntry> schedule,
  Set<String> existingIds,
) => {
  for (final e in schedule.entries)
    if (existingIds.contains(e.key)) e.key: e.value,
};

/// "now" for scheduling; tests replace it.
final reviewClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

/// Per-device review state (shared_preferences, not synced, no schema):
/// each highlight's schedule, whether the home reminder is on, and the day
/// the reminder was last dismissed.
class ReviewSettings extends ChangeNotifier {
  ReviewSettings({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _load();
  }

  final DateTime Function() _clock;

  static const _scheduleKey = 'review.schedule';
  static const _promptKey = 'review.prompt';
  static const _dismissedKey = 'review.dismissedDay';

  Map<String, ReviewEntry> schedule = {};
  bool remind = false;
  String? _dismissedDay;
  bool loaded = false;

  bool get promptDismissedToday => _dismissedDay == _dayKey(_clock());

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      remind = prefs.getBool(_promptKey) ?? false;
      _dismissedDay = prefs.getString(_dismissedKey);
      final raw = prefs.getString(_scheduleKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        schedule = {
          for (final e in map.entries)
            e.key: ReviewEntry(
              keeps: (e.value['k'] as num).toInt(),
              due: DateTime.fromMillisecondsSinceEpoch(
                (e.value['d'] as num).toInt(),
              ),
            ),
        };
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scheduleKey,
        jsonEncode({for (final e in schedule.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }

  Future<void> keep(String highlightId) async {
    schedule = {
      ...schedule,
      highlightId: keepEntry(schedule[highlightId], _clock()),
    };
    notifyListeners();
    await _save();
  }

  Future<void> skip(String highlightId) async {
    schedule = {
      ...schedule,
      highlightId: skipEntry(schedule[highlightId], _clock()),
    };
    notifyListeners();
    await _save();
  }

  /// Forgets highlights that were deleted.
  Future<void> prune(Set<String> existingIds) async {
    final pruned = pruneSchedule(schedule, existingIds);
    if (pruned.length == schedule.length) return;
    schedule = pruned;
    notifyListeners();
    await _save();
  }

  Future<void> setRemind(bool value) async {
    remind = value;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_promptKey, value);
    } catch (_) {}
  }

  Future<void> dismissPromptToday() async {
    _dismissedDay = _dayKey(_clock());
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(
        _dismissedKey,
        _dismissedDay!,
      );
    } catch (_) {}
  }
}

final reviewSettingsProvider = ChangeNotifierProvider<ReviewSettings>(
  (ref) => ReviewSettings(clock: ref.read(reviewClockProvider)),
);

/// How many highlights are due now (0 until anything loads).
final dueReviewCountProvider = Provider.autoDispose<int>((ref) {
  final all = ref.watch(allHighlightsProvider).value ?? const [];
  final settings = ref.watch(reviewSettingsProvider);
  return dueHighlights(
    all,
    settings.schedule,
    ref.read(reviewClockProvider)(),
  ).length;
});
