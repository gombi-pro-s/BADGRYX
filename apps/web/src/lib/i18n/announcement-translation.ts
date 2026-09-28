// Pure logic for picking an announcement's text in the current locale --
// no I/O, no "server-only", since a future client-side use (a locale
// switch re-rendering without a full page reload) shouldn't need a
// server-only import to reuse this. See announcement_translations
// (20260922000030_announcement_translations.sql) and ADR 0038.
import type { AnnouncementTranslationRow } from "@/types/database";
import { DEFAULT_LOCALE, type Locale } from "./locales";

export interface AnnouncementText {
  title: string;
  body_markdown: string;
}

/**
 * The base announcements row IS the DEFAULT_LOCALE ('en') text -- a
 * translations row only exists for a non-default locale that has one.
 * Falls back to the base text whenever the current locale is the default,
 * or no translation row exists for it.
 */
export function pickAnnouncementText(
  base: AnnouncementText,
  translations: Pick<AnnouncementTranslationRow, "locale" | "title" | "body_markdown">[],
  locale: Locale,
): AnnouncementText {
  if (locale === DEFAULT_LOCALE) return base;
  const match = translations.find((t) => t.locale === locale);
  return match ? { title: match.title, body_markdown: match.body_markdown } : base;
}
