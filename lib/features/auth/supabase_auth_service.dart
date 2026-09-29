import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'auth_service.dart';

/// [AuthService] backed by Supabase Auth (email/password). Supabase
/// persists the session on-device, so the user stays signed in across
/// restarts — including offline.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final supabase.GoTrueClient _auth;

  static AppUser? _toUser(supabase.User? user) {
    if (user == null) return null;
    return AppUser(id: user.id, email: user.email ?? '');
  }

  @override
  AppUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AppUser?> get authStateChanges async* {
    // onAuthStateChange only emits on changes, so lead with the restored
    // session or a signed-in user would look signed out until they act.
    yield currentUser;
    yield* _auth.onAuthStateChange.map((state) => _toUser(state.session?.user));
  }

  @override
  Future<void> signUp({required String email, required String password}) =>
      _run(() async {
        final response = await _auth.signUp(email: email, password: password);
        if (response.session == null) {
          // Happens when the project requires email confirmation.
          throw const AuthException(
            'Check your email to confirm your account, then sign in.',
          );
        }
      });

  @override
  Future<void> signIn({required String email, required String password}) =>
      _run(() => _auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> signOut() => _run(_auth.signOut);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on supabase.AuthException catch (e) {
      throw AuthException(e.message);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
