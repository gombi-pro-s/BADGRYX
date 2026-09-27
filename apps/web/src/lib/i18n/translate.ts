import { en } from "./messages/en";
import { es } from "./messages/es";
import type { Locale } from "./locales";

export type MessageKey = keyof typeof en;

const DICTIONARIES: Record<Locale, Partial<Record<MessageKey, string>>> = { en, es };

/**
 * Pure lookup + `{param}` interpolation. Falls back to the English
 * dictionary for any key missing in the target locale, and to the raw key
 * itself if even English is missing it (a real, if unlikely, authoring
 * mistake -- rendering the key is more debuggable than a blank string).
 */
export function translate(locale: Locale, key: MessageKey, params?: Record<string, string | number>): string {
  const template = DICTIONARIES[locale]?.[key] ?? en[key] ?? key;
  if (!params) return template;
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in params ? String(params[name]) : match));
}
