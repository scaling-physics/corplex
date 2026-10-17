import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The note text size on a desktop (View → Zoom In / Zoom Out / Actual
/// Size, like Apple Notes). Per device in shared_preferences, never synced.
class NoteZoom extends ChangeNotifier {
  NoteZoom({this.scale = 1});

  static const steps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];
  static const _key = 'notes.zoom';

  double scale;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_key);
      if (saved != null && steps.contains(saved) && saved != scale) {
        scale = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  int get _index {
    var best = 0;
    for (var i = 0; i < steps.length; i++) {
      if ((steps[i] - scale).abs() < (steps[best] - scale).abs()) best = i;
    }
    return best;
  }

  Future<void> zoomIn() => _set(steps[(_index + 1).clamp(0, steps.length - 1)]);
  Future<void> zoomOut() =>
      _set(steps[(_index - 1).clamp(0, steps.length - 1)]);
  Future<void> reset() => _set(1);

  Future<void> _set(double value) async {
    if (value == scale) return;
    scale = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, value);
    } catch (_) {}
  }
}

final noteZoomProvider = ChangeNotifierProvider<NoteZoom>((ref) {
  final zoom = NoteZoom();
  zoom.load();
  return zoom;
});
