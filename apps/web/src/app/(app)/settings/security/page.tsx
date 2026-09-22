import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { MfaEnrollForm } from "./mfa-enroll-form";
import { RemoveFactorButton } from "./remove-factor-button";

export const metadata: Metadata = { title: "Security" };

export default async function SecurityPage() {
  const user = await requireUser();
  const supabase = await createClient();
  const { data: factorsData } = await supabase.auth.mfa.listFactors();
  const verifiedFactors = factorsData?.totp.filter((f) => f.status === "verified") ?? [];

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/settings" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; Settings
      </Link>
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Security</h1>
      <p className="mb-8 text-sm text-foreground-muted">{user.email}</p>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h2 className="text-sm font-semibold text-foreground">Two-factor authentication</h2>
        <p className="mt-1 mb-4 text-xs text-foreground-subtle">
          Add an authenticator app (Google Authenticator, 1Password, Authy, etc.) as a second factor. Once enabled,
          logging in requires both your password and a 6-digit code from the app.
        </p>

        {verifiedFactors.length > 0 && (
          <ul className="mb-4 divide-y divide-border overflow-hidden rounded-lg border border-border">
            {verifiedFactors.map((factor) => (
              <li key={factor.id} className="flex items-center justify-between gap-4 px-4 py-3">
                <div>
                  <p className="text-sm text-foreground">{factor.friendly_name ?? "Authenticator app"}</p>
                  <p className="text-xs text-foreground-subtle">
                    Added {new Date(factor.created_at).toLocaleDateString()}
                  </p>
                </div>
                <RemoveFactorButton factorId={factor.id} />
              </li>
            ))}
          </ul>
        )}

        <MfaEnrollForm />
      </div>
    </div>
  );
}
