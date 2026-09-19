import 'package:flutter_test/flutter_test.dart';

import 'package:corplex/features/auth/auth_service.dart';

void main() {
  late StubAuthService service;

  setUp(() => service = StubAuthService());

  test('starts signed out', () {
    expect(service.currentUser, isNull);
  });

  test('sign in with a valid email/password signs the user in', () async {
    await service.signIn(email: 'reader@example.com', password: 'hunter22');
    expect(service.currentUser?.email, 'reader@example.com');
  });

  test('sign in rejects a malformed email', () async {
    expect(
      () => service.signIn(email: 'not-an-email', password: 'hunter22'),
      throwsA(isA<AuthException>()),
    );
  });

  test('sign in rejects a short password', () async {
    expect(
      () => service.signIn(email: 'reader@example.com', password: 'abc'),
      throwsA(isA<AuthException>()),
    );
  });

  test('sign out clears the current user', () async {
    await service.signIn(email: 'reader@example.com', password: 'hunter22');
    await service.signOut();
    expect(service.currentUser, isNull);
  });

  test('authStateChanges emits on sign in and sign out', () async {
    final states = <AppUser?>[];
    final sub = service.authStateChanges.listen(states.add);

    await service.signIn(email: 'reader@example.com', password: 'hunter22');
    await service.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(states, hasLength(2));
    expect(states[0]?.email, 'reader@example.com');
    expect(states[1], isNull);
    await sub.cancel();
  });
}
