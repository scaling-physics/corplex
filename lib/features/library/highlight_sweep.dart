import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

/// Highlights made in this session that haven't been shown yet. The page
/// overlay that owns a fresh highlight [claim]s it and plays the marker
/// sweep; highlights that merely load or scroll into view are never in
/// here, so they appear at once.
class FreshHighlights extends ChangeNotifier {
  /// A highlight nobody claims (its page isn't on screen) stops being
  /// news after this long.
  static const staleAfter = Duration(seconds: 4);

  final _ids = <String, DateTime>{};

  void add(String id) {
    _ids[id] = DateTime.now();
    notifyListeners();
  }

  bool contains(String id) {
    final at = _ids[id];
    if (at == null) return false;
    if (DateTime.now().difference(at) > staleAfter) {
      _ids.remove(id);
      return false;
    }
    return true;
  }

  /// True once, for a fresh highlight; false for anything else.
  bool claim(String id) {
    if (!contains(id)) return false;
    _ids.remove(id);
    return true;
  }
}

final freshHighlightsProvider = Provider<FreshHighlights>((ref) {
  final fresh = FreshHighlights();
  ref.onDispose(fresh.dispose);
  return fresh;
});

/// How far line [index] of [lines] has been swept at overall progress
/// [t] (0..1): lines start one after another, each taking half the total
/// time, so the last one finishes exactly at t = 1.
double sweepLineProgress(double t, int index, int lines) {
  final step = lines > 1 ? 0.5 / (lines - 1) : 0.0;
  final p = ((t - index * step) / (lines > 1 ? 0.5 : 1.0)).clamp(0.0, 1.0);
  return AppMotion.standard.transform(p);
}

/// The sweep's duration: short passages (one line) take [AppMotion.medium],
/// longer ones [AppMotion.long].
Duration sweepDuration(int lines) =>
    lines > 1 ? AppMotion.long : AppMotion.medium;
