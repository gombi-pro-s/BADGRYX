import "server-only";

import { cookies } from "next/headers";
import { DEFAULT_LOCALE, isSupportedLocale, type Locale } from "./locales";

export const LOCALE_COOKIE_NAME = "icorepen_locale";

/**
 * Cookie-based locale, not URL-prefixed routing (no `/en/...`, `/es/...`
 * segments). Every existing route keeps its exact path; only the strings
 * a locale-aware page chooses to render via translate() change. This is a
 * smaller, honestly-scoped decision than restructuring the whole `(app)`
 * route tree behind a `[locale]` segment -- see ADR 0025.
 */
export async function getLocale(): Promise<Locale> {
  const store = await cookies();
  const value = store.get(LOCALE_COOKIE_NAME)?.value;
  return value && isSupportedLocale(value) ? value : DEFAULT_LOCALE;
}
