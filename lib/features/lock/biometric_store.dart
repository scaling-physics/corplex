import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'note_lock_service.dart';

/// The two plugin calls the store needs, so tests can fake them.
abstract class BiometricPrompt {
  /// Hardware present and at least one biometric enrolled.
  Future<bool> canUseBiometrics();

  /// Shows the system prompt; true only when the reader passed it.
  Future<bool> authenticate(String reason);
}

class LocalAuthPrompt implements BiometricPrompt {
  /// Created on first use: nothing touches the plugin at construction.
  LocalAuthentication? _auth;
  LocalAuthentication get _a => _auth ??= LocalAuthentication();

  @override
  Future<bool> canUseBiometrics() async {
    if (!await _a.canCheckBiometrics) return false;
    if (!await _a.isDeviceSupported()) return false;
    return (await _a.getAvailableBiometrics()).isNotEmpty;
  }

  /// `biometricOnly: false`: the device passcode is accepted after a failed
  /// or unavailable biometric, as in Apple Notes. Friendlier than being
  /// locked out by a wet finger, and the keys are only ever released to
  /// someone who can unlock this device anyway.
  @override
  Future<bool> authenticate(String reason) => _a.authenticate(
    localizedReason: reason,
    biometricOnly: false,
    persistAcrossBackgrounding: true,
  );
}

/// A single string slot; the real one is flutter_secure_storage.
abstract class SecretSlot {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageSlot implements SecretSlot {
  FlutterSecureStorage? _s;
  FlutterSecureStorage get _storage => _s ??= const FlutterSecureStorage(
    // Never synced to iCloud Keychain or restored onto another device.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
    // An ad-hoc signed, sandboxed Mac app has no team id, hence no
    // keychain-access-groups entitlement: use the file-based keychain.
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
      usesDataProtectionKeychain: false,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Face ID / Touch ID / fingerprint unlock for locked notes. The keys sit in
/// the keychain/keystore (this device only); [read] releases them after the
/// system prompt. Never throws: any failure is "not available" / null.
class PluginBiometricKeyStore implements BiometricKeyStore {
  PluginBiometricKeyStore({BiometricPrompt? prompt, SecretSlot? slot})
    : _prompt = prompt ?? LocalAuthPrompt(),
      _slot = slot ?? SecureStorageSlot();

  final BiometricPrompt _prompt;
  final SecretSlot _slot;

  static const slotKey = 'corplex.notes.keys.v1';
  static const _probeKey = 'corplex.probe';

  @override
  Future<bool> available() async {
    try {
      if (!await _prompt.canUseBiometrics()) return false;
      await _slot.write(_probeKey, 'x');
      final back = await _slot.read(_probeKey);
      await _slot.delete(_probeKey);
      return back == 'x';
    } catch (e) {
      debugPrint('Biometric unlock unavailable: $e');
      return false;
    }
  }

  @override
  Future<bool> enabled() async {
    try {
      return await _slot.read(slotKey) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> store(Map<String, List<int>> keys) async {
    await _slot.write(slotKey, encodeKeys(keys));
  }

  @override
  Future<Map<String, List<int>>?> read({required String reason}) async {
    try {
      final raw = await _slot.read(slotKey);
      if (raw == null) return null;
      if (!await _prompt.authenticate(reason)) return null;
      return decodeKeys(raw);
    } catch (e) {
      debugPrint('Biometric read failed: $e');
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _slot.delete(slotKey);
    } catch (_) {}
  }

  @visibleForTesting
  static String encodeKeys(Map<String, List<int>> keys) =>
      jsonEncode({for (final e in keys.entries) e.key: base64Encode(e.value)});

  @visibleForTesting
  static Map<String, List<int>>? decodeKeys(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries) e.key: base64Decode(e.value as String),
      };
    } catch (_) {
      return null;
    }
  }
}
