"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { emailSchema, passwordSchema } from "@/lib/auth/validation";

export interface AuthActionState {
  error: string | null;
}

export async function signUpAction(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");

  const emailResult = emailSchema.safeParse(email);
  if (!emailResult.success) {
    return { error: emailResult.error.issues[0]?.message ?? "Invalid email." };
  }
  const passwordResult = passwordSchema.safeParse(password);
  if (!passwordResult.success) {
    return { error: passwordResult.error.issues[0]?.message ?? "Invalid password." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email: emailResult.data,
    password: passwordResult.data,
    options: {
      emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/auth/callback`,
    },
  });

  if (error) {
    // Supabase returns a generic message for "email already registered" by
    // design (account enumeration protection is a project auth setting --
    // see MANUAL_SETUP.md); we pass it through as-is rather than crafting
    // our own, to avoid accidentally reintroducing an enumeration oracle.
    return { error: error.message };
  }

  redirect("/verify-email");
}

export async function signInAction(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "/dashboard");

  if (!email || !password) {
    return { error: "Email and password are required." };
  }

  const supabase = await createClient();

  // Checked before ever calling GoTrue, using the `anon` role (no session
  // exists yet) -- see docs/adr/0014-login-rate-limiting.md. Fails open on
  // an unexpected RPC error rather than locking everyone out of login.
  const { data: rateLimit } = await supabase.rpc("check_login_rate_limit", { p_email: email });
  const limitRow = rateLimit?.[0];
  if (limitRow && !limitRow.allowed) {
    const minutes = Math.ceil(limitRow.retry_after_seconds / 60);
    return { error: `Too many failed attempts. Try again in ${minutes} minute${minutes === 1 ? "" : "s"}.` };
  }

  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    await supabase.rpc("record_failed_login_attempt", { p_email: email });
    // Deliberately generic: never reveal whether the email exists.
    return { error: "Invalid email or password." };
  }

  await supabase.rpc("clear_login_attempts", { p_email: email });
  redirect(next.startsWith("/") ? next : "/dashboard");
}

export async function signOutAction(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function requestPasswordResetAction(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const email = String(formData.get("email") ?? "");
  const emailResult = emailSchema.safeParse(email);
  if (!emailResult.success) {
    return { error: emailResult.error.issues[0]?.message ?? "Invalid email." };
  }

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(emailResult.data, {
    redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/auth/callback?next=/update-password`,
  });

  // Always show the same success state regardless of whether the email is
  // registered, so this endpoint cannot be used to enumerate accounts.
  return { error: null };
}

export async function updatePasswordAction(
  _prevState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const password = String(formData.get("password") ?? "");
  const passwordResult = passwordSchema.safeParse(password);
  if (!passwordResult.success) {
    return { error: passwordResult.error.issues[0]?.message ?? "Invalid password." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: passwordResult.data });
  if (error) {
    return { error: error.message };
  }

  redirect("/dashboard");
}
