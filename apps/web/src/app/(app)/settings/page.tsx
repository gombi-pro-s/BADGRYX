import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { ProfileForm } from "./profile-form";

export const metadata: Metadata = { title: "Settings" };

export default async function SettingsPage() {
  const user = await requireUser();
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
    </div>
  );
}
