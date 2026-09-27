"use client";

import { useTransition } from "react";
import { setLocaleAction } from "@/lib/i18n/actions";
import { SUPPORTED_LOCALES, type Locale } from "@/lib/i18n/locales";

const LOCALE_LABELS: Record<Locale, string> = { en: "English", es: "Español" };

export function LocaleSwitcher({ currentLocale, currentPath }: { currentLocale: Locale; currentPath: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex items-center gap-1.5">
      {SUPPORTED_LOCALES.map((locale) => (
        <button
          key={locale}
          type="button"
          disabled={pending || locale === currentLocale}
          onClick={() => startTransition(() => setLocaleAction(locale, currentPath))}
          aria-current={locale === currentLocale}
          className={`rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors disabled:cursor-default ${
            locale === currentLocale
              ? "border-accent bg-accent-muted text-accent"
              : "border-border text-foreground-muted hover:border-border-strong"
          }`}
        >
          {LOCALE_LABELS[locale]}
        </button>
      ))}
    </div>
  );
}
