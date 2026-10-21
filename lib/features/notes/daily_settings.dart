import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device choices for daily notes (not synced, like the appearance
/// settings): which template note a new daily note starts from, and which
/// folder it goes in. Both optional.
class DailyNoteSettings extends ChangeNotifier {
  DailyNoteSettings({this.templateId, this.folderId});

  String? templateId;
  String? folderId;

  /// Completes once the saved choices have been read.
  Future<void> ready = Future.value();

  static const _templateKey = 'daily.templateId';
  static const _folderKey = 'daily.folderId';

  void _startLoading() {
    ready = load().then((loaded) {
      // Don't overwrite a choice made before the prefs came back.
      if (templateId == null && folderId == null) {
        templateId = loaded.templateId;
        folderId = loaded.folderId;
        notifyListeners();
      }
    });
  }

  static Future<DailyNoteSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DailyNoteSettings(
        templateId: prefs.getString(_templateKey),
        folderId: prefs.getString(_folderKey),
      );
    } catch (_) {
      return DailyNoteSettings();
    }
  }

  Future<void> setTemplate(String? id) async {
    templateId = id;
    notifyListeners();
    await _save(_templateKey, id);
  }

  Future<void> setFolder(String? id) async {
    folderId = id;
    notifyListeners();
    await _save(_folderKey, id);
  }

  Future<void> _save(String key, String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (_) {}
  }
}

/// Loaded lazily the first time it is read; until [DailyNoteSettings.ready]
/// completes (and under test) the defaults apply.
final dailyNoteSettingsProvider = ChangeNotifierProvider<DailyNoteSettings>(
  (ref) => DailyNoteSettings().._startLoading(),
);
