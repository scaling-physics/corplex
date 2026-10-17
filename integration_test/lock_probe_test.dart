// Probes the real keychain and crypto on a device:
//   flutter test integration_test/lock_probe_test.dart -d macos
// The biometric prompt itself can't be answered by a test, so this checks
// what can be: the keychain round trip the store depends on, and how long
// PBKDF2 at the default iterations takes.
import 'package:corplex/features/lock/biometric_store.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keychain slot round trips on this platform', (tester) async {
    final slot = SecureStorageSlot();
    await slot.write('corplex.probe.test', 'hello');
    expect(await slot.read('corplex.probe.test'), 'hello');
    await slot.delete('corplex.probe.test');
    expect(await slot.read('corplex.probe.test'), isNull);
  });

  testWidgets('store keeps and returns keys without a prompt', (tester) async {
    final store = PluginBiometricKeyStore();
    final keys = {'k': List<int>.generate(32, (i) => i)};
    await store.store(keys);
    expect(await store.enabled(), isTrue);
    await store.clear();
    expect(await store.enabled(), isFalse);
    // Must complete (true or false) and never throw.
    final available = await store.available();
    // ignore: avoid_print
    print('biometric available: $available');
  });

  testWidgets('PBKDF2 at the default iterations: time', (tester) async {
    final crypto = NoteCrypto();
    final salt = crypto.newSalt();
    final sw = Stopwatch()..start();
    final kek = await crypto.deriveKek(
      'correct horse',
      salt,
      NoteCrypto.defaultIterations,
    );
    sw.stop();
    expect(kek.length, 32);
    // ignore: avoid_print
    print(
      'PBKDF2 ${NoteCrypto.defaultIterations}: ${sw.elapsedMilliseconds} ms',
    );
  });
}
