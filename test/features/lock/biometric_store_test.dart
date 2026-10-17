import 'package:corplex/features/lock/biometric_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prompt implements BiometricPrompt {
  _Prompt({this.can = true, this.pass = true, this.throws = false});
  final bool can, pass, throws;
  @override
  Future<bool> canUseBiometrics() async {
    if (throws) throw Exception('no plugin');
    return can;
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (throws) throw Exception('locked out');
    return pass;
  }
}

class _Slot implements SecretSlot {
  final map = <String, String>{};
  bool broken = false;
  @override
  Future<String?> read(String key) async {
    if (broken) throw Exception('keychain');
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw Exception('keychain');
    map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (broken) throw Exception('keychain');
    map.remove(key);
  }
}

void main() {
  final keys = {
    'a': List<int>.generate(32, (i) => i),
    'b': List<int>.filled(32, 255),
  };

  test('keys round trip through JSON of base64', () {
    final raw = PluginBiometricKeyStore.encodeKeys(keys);
    expect(PluginBiometricKeyStore.decodeKeys(raw), keys);
    expect(PluginBiometricKeyStore.decodeKeys('nonsense'), isNull);
  });

  test('store, enabled, read, clear', () async {
    final s = PluginBiometricKeyStore(prompt: _Prompt(), slot: _Slot());
    expect(await s.enabled(), isFalse);
    expect(await s.read(reason: 'x'), isNull);
    await s.store(keys);
    expect(await s.enabled(), isTrue);
    expect(await s.read(reason: 'x'), keys);
    await s.clear();
    expect(await s.enabled(), isFalse);
  });

  test('cancelled or failed prompt returns null, never throws', () async {
    final slot = _Slot();
    await PluginBiometricKeyStore(prompt: _Prompt(), slot: slot).store(keys);
    final denied = PluginBiometricKeyStore(
      prompt: _Prompt(pass: false),
      slot: slot,
    );
    expect(await denied.read(reason: 'x'), isNull);
    final broken = PluginBiometricKeyStore(
      prompt: _Prompt(throws: true),
      slot: slot,
    );
    expect(await broken.read(reason: 'x'), isNull);
  });

  test('available is false without biometrics or a working keychain', () async {
    expect(
      await PluginBiometricKeyStore(
        prompt: _Prompt(),
        slot: _Slot(),
      ).available(),
      isTrue,
    );
    expect(
      await PluginBiometricKeyStore(
        prompt: _Prompt(can: false),
        slot: _Slot(),
      ).available(),
      isFalse,
    );
    expect(
      await PluginBiometricKeyStore(
        prompt: _Prompt(throws: true),
        slot: _Slot(),
      ).available(),
      isFalse,
    );
    final bad = _Slot()..broken = true;
    final s = PluginBiometricKeyStore(prompt: _Prompt(), slot: bad);
    expect(await s.available(), isFalse);
    expect(await s.enabled(), isFalse);
    expect(await s.read(reason: 'x'), isNull);
    await s.clear();
  });
}
