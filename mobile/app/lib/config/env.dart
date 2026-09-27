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

/// Unlike SupabaseEnv, this is optional: the app has a real backend
/// (Supabase) without it, so a build with no API_BASE_URL still works for
/// every Supabase-only screen. Only the AI Mentor screen -- the one
/// feature that calls apps/web's Next.js Route Handlers directly, not
/// Supabase -- degrades to a plain "not configured on this build" message
/// (see mentor_screen.dart), the same "optional integration degrades
/// gracefully, core functionality never blocked" pattern already used for
/// Turnstile/billing providers on the web app.
class AppEnv {
  const AppEnv._();

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isMentorConfigured => apiBaseUrl.isNotEmpty;
}
