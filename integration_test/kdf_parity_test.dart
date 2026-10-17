import 'dart:io' show Platform;

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:corplex/features/lock/note_crypto.dart';

/// The notes password must derive the same key on every platform, or a
/// password set on one device would be "wrong" on another. On Android the
/// production path is native (javax.crypto via cryptography_flutter); this
/// compares it with the pure-Dart path the other platforms use.
/// `flutter test integration_test/kdf_parity_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final crypto = NoteCrypto();
  final salt = List<int>.generate(16, (i) => i * 7 + 3);

  for (final password in const [
    'correct horse battery',
    'Grüße, Zoë — 東京 🔒',
  ]) {
    testWidgets('same key on this platform as in pure Dart: $password', (
      tester,
    ) async {
      final platform = await crypto.deriveKek(password, salt, 20000);
      final dart = await crypto.deriveKek(password, salt, 20000, inline: true);
      expect(platform, dart);
    });
  }

  testWidgets('Android really derives natively (no silent fallback)', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    final native = FlutterPbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 20000,
      bits: 256,
    ); // no fallback: throws if the plugin isn't there
    final key = await native.deriveKeyFromPassword(
      password: NoteCrypto.kdfInput('Grüße, Zoë — 東京 🔒'),
      nonce: salt,
    );
    final dart = await crypto.deriveKek(
      'Grüße, Zoë — 東京 🔒',
      salt,
      20000,
      inline: true,
    );
    expect(await key.extractBytes(), dart);
  });
}
