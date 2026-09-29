/// Supabase project credentials, supplied at build time so they never live
/// in the repo:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR-PUBLISHABLE-KEY
/// ```
///
/// The publishable key (formerly "anon key") is designed to ship inside the app; row-level security
/// (supabase/migrations) is what protects each user's data. Without both
/// values the app runs fully offline with no account, exactly as before.
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
