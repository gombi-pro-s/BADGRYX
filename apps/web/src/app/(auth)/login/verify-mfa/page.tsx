import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { VerifyMfaForm } from "./verify-mfa-form";

export const metadata: Metadata = { title: "Verify your identity" };

export default async function VerifyMfaPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;

  // Deliberately NOT requireUser() -- that call itself redirects here when
  // step-up is needed, which would loop. A password-only (aal1) session is
  // exactly what this page is for; getCurrentUser() just confirms *some*
  // session exists.
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login");
  }

  const supabase = await createClient();
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  const stepUpNeeded = aal && aal.nextLevel === "aal2" && aal.currentLevel !== aal.nextLevel;
  if (!stepUpNeeded) {
    // Nothing to verify -- most likely the user navigated here directly
    // without MFA enrolled, or already completed it this session.
    redirect(next && next.startsWith("/") ? next : "/dashboard");
  }

  return (
    <div>
      <h1 className="text-xl font-semibold text-foreground">Verify your identity</h1>
      <p className="mt-1 text-sm text-foreground-muted">
        Enter the 6-digit code from your authenticator app.
      </p>
      <div className="mt-6">
        <VerifyMfaForm next={next} />
      </div>
    </div>
  );
}
