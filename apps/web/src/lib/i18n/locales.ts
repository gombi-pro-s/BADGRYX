/**
 * The full set of locales this app can render UI strings in. Adding a
 * locale means adding a messages/<locale>.ts dictionary and this array --
 * nothing else needs to change, since translate() (see translate.ts)
 * already falls back to DEFAULT_LOCALE for any key a new dictionary
 * hasn't caught up on yet.
 */
export const SUPPORTED_LOCALES = ["en", "es"] as const;
export type Locale = (typeof SUPPORTED_LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

export function isSupportedLocale(value: string): value is Locale {
  return (SUPPORTED_LOCALES as readonly string[]).includes(value);
}
