import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

/// The signed-in user's identity. Only what the app currently needs.
class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String email;
}

/// Abstraction over "who is signed in and how do they sign in/out",
/// so the real backend (Supabase Auth) can be dropped in later without
/// touching the screens that depend on this interface.
abstract class AuthService {
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  Future<void> signUp({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

/// Placeholder implementation used until a real Supabase project exists.
/// Accepts any well-formed email/password, "signs in" instantly, and keeps
/// the session only in memory (lost on app restart) — enough to build and
/// test the auth screens and the rest of the app's navigation around them.
class StubAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<void> signUp({required String email, required String password}) =>
      signIn(email: email, password: password);

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (!email.contains('@')) {
      throw const AuthException(
        'Enter a valid email address.',
        code: AuthErrorCode.invalidEmail,
      );
    }
    if (password.length < 6) {
      throw const AuthException(
        'Password must be at least 6 characters.',
        code: AuthErrorCode.shortPassword,
      );
    }
    _currentUser = AppUser(id: email, email: email);
    _controller.add(_currentUser);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }
}

/// The failures the app words itself (a server's own message has no code).
enum AuthErrorCode {
  invalidEmail,
  shortPassword,
  confirmEmail,
  offline,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.message, {this.code, this.detail});

  /// English text, for logs and tests; screens show [authErrorText].
  final String message;
  final AuthErrorCode? code;

  /// What [AuthErrorCode.unknown] names (the exception's type).
  final String? detail;

  @override
  String toString() => message;
}

/// [error] in the app's language: the app's own failures are translated, a
/// message that came from the server is shown as it arrived.
String authErrorText(AppLocalizations l10n, Object error) {
  if (error is AuthException) {
    return switch (error.code) {
      AuthErrorCode.invalidEmail => l10n.authInvalidEmail,
      AuthErrorCode.shortPassword => l10n.authShortPassword,
      AuthErrorCode.confirmEmail => l10n.authConfirmEmail,
      AuthErrorCode.offline => l10n.authOffline,
      AuthErrorCode.unknown => l10n.authUnknown(error.detail ?? ''),
      null => error.message,
    };
  }
  return error.toString();
}

final authServiceProvider = Provider<AuthService>((ref) => StubAuthService());

final authStateProvider = StreamProvider<AppUser?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges;
});
