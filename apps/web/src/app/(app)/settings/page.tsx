import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { LocaleSwitcher } from "@/components/locale-switcher";
import { getLocale } from "@/lib/i18n/cookie";
import { translate } from "@/lib/i18n/translate";
import { ProfileForm } from "./profile-form";

export const metadata: Metadata = { title: "Settings" };

export default async function SettingsPage() {
  const [user, locale] = await Promise.all([requireUser(), getLocale()]);
  const supabase = await createClient();
  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name, username, bio, timezone")
    .eq("id", user.id)
    .single();

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <h1 className="text-2xl font-semibold text-foreground">Settings</h1>
      <p className="mt-1 text-sm text-foreground-muted">{user.email}</p>

      <div className="mt-8 rounded-lg border border-border bg-surface p-6">
        <h2 className="text-sm font-semibold text-foreground">Profile</h2>
        <div className="mt-4">
          <ProfileForm
            initial={{
              display_name: profile?.display_name ?? "",
              username: profile?.username ?? "",
              bio: profile?.bio ?? "",
              timezone: profile?.timezone ?? "UTC",
            }}
          />
        </div>
      </div>

      <Link
        href="/settings/security"
        className="mt-6 block rounded-lg border border-border bg-surface p-6 hover:border-border-strong"
      >
        <h2 className="text-sm font-semibold text-foreground">Security</h2>
        <p className="mt-1 text-xs text-foreground-subtle">
          Add two-factor authentication with an authenticator app.
        </p>
      </Link>

      <Link
        href="/settings/billing"
        className="mt-6 block rounded-lg border border-border bg-surface p-6 hover:border-border-strong"
      >
        <h2 className="text-sm font-semibold text-foreground">Billing</h2>
        <p className="mt-1 text-xs text-foreground-subtle">View your plan and entitlements, or upgrade.</p>
      </Link>

      <Link
        href="/settings/privacy"
        className="mt-6 block rounded-lg border border-border bg-surface p-6 hover:border-border-strong"
      >
        <h2 className="text-sm font-semibold text-foreground">Privacy &amp; data</h2>
        <p className="mt-1 text-xs text-foreground-subtle">Export your data, or permanently delete your account.</p>
      </Link>

      <div className="mt-6 rounded-lg border border-border bg-surface p-6">
        <h2 className="text-sm font-semibold text-foreground">{translate(locale, "settings.language.heading")}</h2>
        <p className="mt-1 text-xs text-foreground-subtle">{translate(locale, "settings.language.description")}</p>
        <div className="mt-4">
          <LocaleSwitcher currentLocale={locale} currentPath="/settings" />
        </div>
      </div>
    </div>
  );
}
