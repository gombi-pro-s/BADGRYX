import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors `lib/i18n/locales.ts` exactly: the full set of locales this
/// app can render translated content in, and the default ('en') that
/// every base row (announcements, learning paths, lessons) already is.
const List<String> supportedLocales = ['en', 'es'];
const String defaultLocale = 'en';

bool isSupportedLocale(String value) => supportedLocales.contains(value);

/// Mirrors `lib/i18n/cookie.ts`'s role, not its storage: web persists the
/// chosen locale in a cookie read on every server-rendered request; this
/// app has no server-rendered request to attach a cookie to, so it
/// persists the same single string with `shared_preferences` instead --
/// the same on-device key-value store `supabase_flutter` already uses to
/// keep a session across restarts. No cross-device sync either way (web's
/// cookie doesn't follow a device to a different browser).
class LocaleStore {
  static const String _key = 'icorepen_locale';

  /// Falls back to [defaultLocale] exactly like `getLocale()` does for a
  /// missing or unrecognized cookie value.
  static Future<String> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    return value != null && isSupportedLocale(value) ? value : defaultLocale;
  }

  static Future<void> setLocale(String locale) async {
    if (!isSupportedLocale(locale)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale);
  }
}
