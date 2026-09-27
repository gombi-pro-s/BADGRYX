import Link from "next/link";
import { ButtonLink } from "@/components/ui/button-link";
import { LocaleSwitcher } from "@/components/locale-switcher";
import { getCurrentUser } from "@/lib/auth/session";
import { getLocale } from "@/lib/i18n/cookie";
import { translate } from "@/lib/i18n/translate";

export default async function HomePage() {
  const [user, locale] = await Promise.all([getCurrentUser(), getLocale()]);
  const t = (key: Parameters<typeof translate>[1]) => translate(locale, key);

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex h-16 items-center justify-between border-b border-border px-6">
        <span className="font-mono text-base font-semibold tracking-tight">
          iCore<span className="text-accent">Pen</span>
        </span>
        <nav className="flex items-center gap-3">
          <LocaleSwitcher currentLocale={locale} currentPath="/" />
          {user ? (
            <ButtonLink href="/dashboard" size="sm">
              {t("landing.nav.dashboard")}
            </ButtonLink>
          ) : (
            <>
              <Link href="/login" className="text-sm font-medium text-foreground-muted hover:text-foreground">
                {t("landing.nav.login")}
              </Link>
              <ButtonLink href="/signup" size="sm">
                {t("landing.nav.signup")}
              </ButtonLink>
            </>
          )}
        </nav>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center px-6 py-24 text-center">
        <p className="font-mono text-xs uppercase tracking-widest text-accent">{t("landing.tagline")}</p>
        <h1 className="mt-4 max-w-2xl text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">
          {t("landing.heading")}
        </h1>
        <p className="mt-5 max-w-xl text-base text-foreground-muted">{t("landing.subheading")}</p>
        <div className="mt-8 flex items-center gap-3">
          <ButtonLink href="/signup" size="lg">
            {t("landing.cta.startLearning")}
          </ButtonLink>
          <ButtonLink href="/login" size="lg" variant="secondary">
            {t("landing.cta.login")}
          </ButtonLink>
        </div>
      </main>

      <footer className="border-t border-border px-6 py-6 text-center text-xs text-foreground-subtle">
        {t("landing.footer")}
      </footer>
    </div>
  );
}
