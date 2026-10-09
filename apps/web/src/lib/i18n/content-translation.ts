// Pure logic for picking a learning path's or lesson's text in the
// current locale -- same shape as pickAnnouncementText() in
// announcement-translation.ts, no I/O, no "server-only". See
// learning_path_translations/lesson_translations
// (20260922000032_content_translations.sql) and ADR 0064.
import type { LearningPathTranslationRow, LessonTranslationRow } from "@/types/database";
import { DEFAULT_LOCALE, type Locale } from "./locales";

export interface PathText {
  title: string;
  description: string | null;
}

export interface LessonText {
  title: string;
  content_markdown: string;
}

/**
 * The base learning_paths row IS the DEFAULT_LOCALE ('en') text -- a
 * translation row only exists for a non-default locale that has one.
 * Falls back to the base text whenever the current locale is the default,
 * or no translation row exists for it.
 */
export function pickPathText(
  base: PathText,
  translations: Pick<LearningPathTranslationRow, "locale" | "title" | "description">[],
  locale: Locale,
): PathText {
  if (locale === DEFAULT_LOCALE) return base;
  const match = translations.find((t) => t.locale === locale);
  return match ? { title: match.title, description: match.description } : base;
}

/** Same rule as pickPathText(), applied to a lesson's title/content_markdown. */
export function pickLessonText(
  base: LessonText,
  translations: Pick<LessonTranslationRow, "locale" | "title" | "content_markdown">[],
  locale: Locale,
): LessonText {
  if (locale === DEFAULT_LOCALE) return base;
  const match = translations.find((t) => t.locale === locale);
  return match ? { title: match.title, content_markdown: match.content_markdown } : base;
}
