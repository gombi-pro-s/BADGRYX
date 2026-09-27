/// Central place that reads Supabase config, mirroring apps/web's
/// lib/supabase/env.ts: a missing config must fail clearly and visibly
/// (see main.dart's ConfigMissingScreen), never silently fall back to
/// mock data.
///
/// Values are compile-time constants supplied via `--dart-define` (see
/// mobile/app/README.md for the exact `flutter run`/`flutter build`
/// invocation) -- no `.env` file bundled into the app binary, and no new
/// dependency (`flutter_dotenv` etc.) just to read two strings.
class SupabaseEnv {
  const SupabaseEnv._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => isSupabaseConfigured(url, anonKey);
}

/// Pure so it's unit-testable without needing real `--dart-define` values
/// at test time.
bool isSupabaseConfigured(String url, String anonKey) {
  return url.isNotEmpty && anonKey.isNotEmpty;
}
