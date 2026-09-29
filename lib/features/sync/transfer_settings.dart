import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_sync.dart';

/// How PDFs, audio and images move between devices. Both are per-device
/// preferences, kept out of the synced database on purpose (a phone on a
/// data plan and an iPad on home Wi-Fi want different answers).
///
/// * [wifiOnly] (default on): files upload and auto-download only on Wi-Fi
///   or Ethernet. Opening a file downloads it on any network — the reader
///   asked for it.
/// * [onDemand] (default off): never auto-download; each file is fetched
///   when it is opened.
class TransferSettings extends ChangeNotifier {
  TransferSettings({this.wifiOnly = true, this.onDemand = false});

  bool wifiOnly;
  bool onDemand;

  static const _wifiKey = 'transfer.wifiOnly';
  static const _demandKey = 'transfer.onDemand';

  static Future<TransferSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return TransferSettings(
        wifiOnly: prefs.getBool(_wifiKey) ?? true,
        onDemand: prefs.getBool(_demandKey) ?? false,
      );
    } catch (_) {
      return TransferSettings();
    }
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    notifyListeners();
    await _save(_wifiKey, value);
  }

  Future<void> setOnDemand(bool value) async {
    onDemand = value;
    notifyListeners();
    await _save(_demandKey, value);
  }

  Future<void> _save(String key, bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, value);
    } catch (_) {}
  }
}

/// Wi-Fi or Ethernet, as opposed to mobile data (or nothing).
bool isUnmetered(List<ConnectivityResult> results) =>
    results.contains(ConnectivityResult.wifi) ||
    results.contains(ConnectivityResult.ethernet);

/// The policy for [settings] on the given network. Pure, so it's testable.
FileTransferPolicy policyFor(
  TransferSettings settings, {
  required bool unmetered,
}) {
  final allowed = !settings.wifiOnly || unmetered;
  return FileTransferPolicy(
    upload: allowed,
    autoDownload: allowed && !settings.onDemand,
  );
}

/// The app-wide settings. Loaded from disk at startup ([transferSettings]
/// is replaced by an override in `main`); defaults until then.
final transferSettingsProvider = ChangeNotifierProvider<TransferSettings>(
  (ref) => TransferSettings(),
);

/// Resolves the live policy: settings plus the current network. If the
/// network can't be determined, assume it is metered.
PolicyResolver liveTransferPolicy(TransferSettings settings) => () async {
  var unmetered = false;
  try {
    unmetered = isUnmetered(await Connectivity().checkConnectivity());
  } catch (_) {}
  return policyFor(settings, unmetered: unmetered);
};
