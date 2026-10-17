import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/data/database.dart';
import 'package:corplex/features/lock/note_crypto.dart';
import 'package:corplex/features/lock/note_lock_service.dart';

const _body = '[{"insert":"Grant draft: the real numbers\\n"}]';

class _FakeBiometrics implements BiometricKeyStore {
  Map<String, List<int>>? stored;
  bool approve = true;

  @override
  Future<bool> available() async => true;
  @override
  Future<bool> enabled() async => stored != null;
  @override
  Future<void> store(Map<String, List<int>> keys) async => stored = keys;
  @override
  Future<Map<String, List<int>>?> read({required String reason}) async =>
      approve ? stored : null;
  @override
  Future<void> clear() async => stored = null;
}

void main() {
  late AppDatabase db;

  NoteLockService service({BiometricKeyStore? biometrics}) => NoteLockService(
    db,
    crypto: NoteCrypto(iterations: 1000),
    biometrics: biometrics ?? const NoBiometrics(),
    inlineKdf: true,
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.inMemoryForTesting();
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: const Value('n1'),
            title: const Value('Grant'),
            content: const Value(_body),
          ),
        );
  });
  tearDown(() => db.close());

  Future<Note> note(String id) =>
      (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

  group('NoteCrypto', () {
    final crypto = NoteCrypto(iterations: 1000);
    const key = NoteKey('k1', [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
      17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    ]);

    test('round trip, with a fresh nonce each time', () async {
      final a = await crypto.encrypt(key, 'n1', _body);
      final b = await crypto.encrypt(key, 'n1', _body);
      expect(isLockedContent(a), isTrue);
      expect(lockedKeyId(a), 'k1');
      expect(a, isNot(b));
      expect(a, isNot(contains('Grant')));
      expect(await crypto.decrypt(key, 'n1', a), _body);
    });

    test('a body is bound to its note', () async {
      final a = await crypto.encrypt(key, 'n1', _body);
      expect(
        () => crypto.decrypt(key, 'n2', a),
        throwsA(isA<NoteDecryptException>()),
      );
    });

    test('tampering is detected', () async {
      final a = await crypto.encrypt(key, 'n1', _body);
      final flipped =
          a.substring(0, a.length - 6) +
          (a[a.length - 6] == 'A' ? 'B' : 'A') +
          a.substring(a.length - 5);
      expect(
        () => crypto.decrypt(key, 'n1', flipped),
        throwsA(isA<NoteDecryptException>()),
      );
    });

    test('ordinary content is not mistaken for a locked body', () {
      expect(isLockedContent(_body), isFalse);
      expect(isLockedContent('plain old text'), isFalse);
      expect(lockedKeyId(_body), isNull);
    });

    test('a wrong password fails to unwrap', () async {
      final salt = crypto.newSalt();
      final kek = await crypto.deriveKek('right', salt, 1000, inline: true);
      final wrong = await crypto.deriveKek('wrong', salt, 1000, inline: true);
      final wrapped = await crypto.wrap(kek, key.bytes);
      expect(await crypto.unwrap(kek, wrapped), key.bytes);
      expect(await crypto.unwrap(wrong, wrapped), isNull);
    });
  });

  group('NoteLockService', () {
    test('lock a note: body and versions encrypted, readable once '
        'unlocked', () async {
      await db
          .into(db.noteVersions)
          .insert(
            NoteVersionsCompanion.insert(
              id: const Value('v1'),
              noteId: 'n1',
              content: const Value(_body),
            ),
          );
      final s = service();
      await s.setPassword('hunter22', hint: 'the usual');
      await s.lockNote('n1');

      final locked = await note('n1');
      expect(isLockedContent(locked.content), isTrue);
      expect(locked.title, 'Grant', reason: 'titles stay readable');
      final version = await db.select(db.noteVersions).getSingle();
      expect(isLockedContent(version.content), isTrue);
      expect(await s.decryptBody('n1', locked.content), _body);
      expect(await s.decryptBody('n1', version.content), _body);

      s.lockNow();
      expect(s.canRead(locked.content), isFalse);
      expect(
        () => s.decryptBody('n1', locked.content),
        throwsA(isA<NoteLockedException>()),
      );
      expect(await s.unlock('wrong'), isFalse);
      expect(await s.unlock('hunter22'), isTrue);
      expect(await s.decryptBody('n1', locked.content), _body);
      expect(await s.hint(), 'the usual');
    });

    test('no plain text stays in the sync merge base', () async {
      final s = service();
      await s.setPassword('hunter22');
      await s.lockNote('n1');
      final base = await db.customSelect('SELECT data FROM sync_base').get();
      for (final row in base) {
        expect(row.read<String>('data'), isNot(contains('real numbers')));
      }
    });

    test('remove the lock', () async {
      final s = service();
      await s.setPassword('hunter22');
      await s.lockNote('n1');
      await s.removeLock('n1');
      expect((await note('n1')).content, _body);
    });

    test(
      'a new body is written locked; plain content passes through',
      () async {
        final s = service();
        await s.setPassword('hunter22');
        final env = await s.encryptBody('n1', _body);
        expect(isLockedContent(env), isTrue);
        expect(await s.decryptBody('n1', _body), _body);
      },
    );

    test('change the password', () async {
      final s = service();
      await s.setPassword('old-pass');
      await s.lockNote('n1');
      expect(await s.changePassword('nope', 'new-pass'), isFalse);
      expect(await s.changePassword('old-pass', 'new-pass'), isTrue);
      s.lockNow();
      expect(await s.unlock('old-pass'), isFalse);
      expect(await s.unlock('new-pass'), isTrue);
      expect(await s.decryptBody('n1', (await note('n1')).content), _body);
    });

    test('a reset password leaves old notes under the old one', () async {
      final s = service();
      await s.setPassword('forgotten');
      await s.lockNote('n1');
      s.lockNow();
      await s.resetPassword('fresh-start');
      final old = (await note('n1')).content;
      expect(s.canRead(old), isFalse);
      expect(await s.isUnlocked(), isTrue, reason: 'new key is current');
      expect(await s.unlock('forgotten'), isTrue);
      expect(s.canRead(old), isTrue);
    });

    test('another device unlocks with the same password', () async {
      final a = service();
      await a.setPassword('shared-pass');
      await a.lockNote('n1');
      final b = service(); // same synced rows, nothing in memory
      expect(await b.isUnlocked(), isFalse);
      expect(await b.unlock('shared-pass'), isTrue);
      expect(await b.decryptBody('n1', (await note('n1')).content), _body);
    });

    test('biometrics unlock without the password', () async {
      final bio = _FakeBiometrics();
      final s = service(biometrics: bio);
      await s.setPassword('hunter22');
      await s.setBiometrics(true);
      await s.lockNote('n1');
      s.lockNow();
      bio.approve = false;
      expect(await s.unlockWithBiometrics(), isFalse);
      bio.approve = true;
      expect(await s.unlockWithBiometrics(), isTrue);
      expect(await s.decryptBody('n1', (await note('n1')).content), _body);
      await s.setBiometrics(false);
      s.lockNow();
      expect(await s.unlockWithBiometrics(), isFalse);
    });

    test('locks itself after the idle time', () {
      fakeAsync((clock) {
        final s = NoteLockService(
          db,
          crypto: NoteCrypto(iterations: 1000),
          inlineKdf: true,
          autoLockAfter: const Duration(minutes: 5),
        );
        s.setPassword('hunter22');
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 1));
        expect(s.anyUnlocked, isTrue);
        clock.elapse(const Duration(minutes: 4));
        s.touch();
        clock.elapse(const Duration(minutes: 4));
        expect(s.anyUnlocked, isTrue);
        clock.elapse(const Duration(minutes: 2));
        expect(s.anyUnlocked, isFalse);
      });
    });
  });
}
