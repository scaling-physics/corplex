import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:flutter_riverpod/legacy.dart';

import 'nav_target.dart';

/// One entry of the history: where, and how far the reader had scrolled
/// (a fraction 0..1 of the page/note, null until something reports it).
class NavEntry {
  const NavEntry(this.target, {this.scroll});

  final NavTarget target;
  final double? scroll;

  NavEntry withScroll(double? scroll) => NavEntry(target, scroll: scroll);
}

/// Back/forward across notes, papers and projects: a browser-style stack.
/// Pure (no Flutter): [visit] records a place, [back]/[forward] move and
/// return the entry to show. Visiting the place already current only
/// refreshes it (so a re-selection or a selection change within the same
/// note doesn't grow the history); visiting from the middle drops what was
/// ahead, as a browser does.
class NavHistory {
  NavHistory({this.limit = 100});

  final int limit;
  final List<NavEntry> _entries = [];
  int _at = -1;

  List<NavEntry> get entries => List.unmodifiable(_entries);
  int get index => _at;
  NavEntry? get current => _at >= 0 ? _entries[_at] : null;
  bool get canGoBack => _at > 0;
  bool get canGoForward => _at >= 0 && _at < _entries.length - 1;

  void visit(NavTarget target) {
    final cur = current;
    if (cur != null && cur.target.key == target.key) {
      // Same place: keep the scroll, take the newer target (it may carry a
      // selection).
      _entries[_at] = NavEntry(target, scroll: cur.scroll);
      return;
    }
    if (_at < _entries.length - 1) {
      _entries.removeRange(_at + 1, _entries.length);
    }
    _entries.add(NavEntry(target));
    if (_entries.length > limit) _entries.removeAt(0);
    _at = _entries.length - 1;
  }

  /// Records how far the current place is scrolled.
  void reportScroll(double? scroll) {
    if (_at >= 0) _entries[_at] = _entries[_at].withScroll(scroll);
  }

  /// Records the scroll of the place keyed [targetKey] even when it is no
  /// longer the current one (an editor reports as it closes, by which time
  /// the next place has been visited). The entry nearest the current one
  /// wins when a place appears twice.
  void reportScrollFor(String targetKey, double? scroll) {
    if (_at < 0) return;
    var best = -1;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].target.key != targetKey) continue;
      if (best < 0 || (i - _at).abs() < (best - _at).abs()) best = i;
    }
    if (best >= 0) _entries[best] = _entries[best].withScroll(scroll);
  }

  NavEntry? back() {
    if (!canGoBack) return null;
    return _entries[--_at];
  }

  NavEntry? forward() {
    if (!canGoForward) return null;
    return _entries[++_at];
  }

  /// Forgets [targetKey] (a deleted note or paper): back/forward skip it.
  void forget(String targetKey) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].target.key != targetKey) continue;
      _entries.removeAt(i);
      if (i <= _at) _at--;
    }
    // Collapse neighbours that are now the same place.
    for (var i = _entries.length - 1; i > 0; i--) {
      if (_entries[i].target.key == _entries[i - 1].target.key) {
        _entries.removeAt(i);
        if (i <= _at) _at--;
      }
    }
    if (_entries.isEmpty) {
      _at = -1;
    } else if (_at < 0) {
      _at = 0;
    }
  }

  void clear() {
    _entries.clear();
    _at = -1;
  }
}

/// The app's history, plus a counter that changes whenever it does, for UI
/// that shows or enables Back/Forward. Home-level state: one history for the
/// window.
class NavHistoryNotifier extends StateNotifier<int> {
  NavHistoryNotifier() : super(0);

  final history = NavHistory();

  void visit(NavTarget target) {
    history.visit(target);
    state++;
  }

  void reportScroll(double? scroll) => history.reportScroll(scroll);

  void reportScrollFor(String targetKey, double? scroll) =>
      history.reportScrollFor(targetKey, scroll);

  NavEntry? back() {
    final e = history.back();
    if (e != null) state++;
    return e;
  }

  NavEntry? forward() {
    final e = history.forward();
    if (e != null) state++;
    return e;
  }

  void forget(String targetKey) {
    history.forget(targetKey);
    state++;
  }
}

final navHistoryProvider = StateNotifierProvider<NavHistoryNotifier, int>(
  (ref) => NavHistoryNotifier(),
);

/// Set while back/forward is replaying an entry, so opening it isn't
/// recorded as a new visit.
final navReplayingProvider = StateProvider<bool>((ref) => false);

/// Notes a visit in the window's history, unless back/forward is replaying
/// one. The one call every opener that doesn't go through `openNote` /
/// `openPaper` makes.
void recordNavVisit(WidgetRef ref, NavTarget target) {
  if (ref.read(navReplayingProvider)) return;
  ref.read(navHistoryProvider.notifier).visit(target);
}
