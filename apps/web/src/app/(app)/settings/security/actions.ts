"use server";

import { revalidatePath } from "next/cache";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logAuditEvent } from "@/lib/audit";

export interface EnrollTotpState {
  error: string | null;
  factorId: string | null;
  qrCode: string | null;
  secret: string | null;
}

export interface FormState {
  error: string | null;
}

/**
 * Starts TOTP enrollment. Any previously abandoned (never-verified) TOTP
 * factor for this user is removed first -- otherwise repeated attempts
 * (scan didn't work, tab closed, etc.) would pile up unverified factors
 * with no way for the user to clean them up themselves.
 */
export async function enrollTotpFactorAction(): Promise<EnrollTotpState> {
  const user = await requireUser();
  const supabase = await createClient();

  const { data: existing } = await supabase.auth.mfa.listFactors();
  const abandoned = existing?.all.filter((f) => f.factor_type === "totp" && f.status === "unverified") ?? [];
  for (const factor of abandoned) {
    await supabase.auth.mfa.unenroll({ factorId: factor.id });
  }

  const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp" });
  if (error || !data || data.type !== "totp") {
    return { error: error?.message ?? "Could not start enrollment.", factorId: null, qrCode: null, secret: null };
  }

  await logAuditEvent(supabase, "mfa.enrollment_started", "user", user.id);

  return { error: null, factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret };
}

export async function verifyTotpEnrollmentAction(
  factorId: string,
  _prevState: FormState,
  formData: FormData,
): Promise<FormState> {
  const user = await requireUser();
  const code = String(formData.get("code") ?? "").trim();
  if (!/^\d{6}$/.test(code)) {
    return { error: "Enter the 6-digit code from your authenticator app." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
  if (error) {
    return { error: "Invalid or expired code. Try again." };
  }

  await logAuditEvent(supabase, "mfa.enrollment_completed", "user", user.id);
  revalidatePath("/settings/security");
  return { error: null };
}

export async function unenrollFactorAction(factorId: string): Promise<void> {
  const user = await requireUser();
  const supabase = await createClient();
  const { error } = await supabase.auth.mfa.unenroll({ factorId });
  if (error) {
    throw new Error(error.message);
  }
  await logAuditEvent(supabase, "mfa.factor_removed", "user", user.id, null, { factor_id: factorId });
  revalidatePath("/settings/security");
}
