import { NextResponse } from "next/server";
import { requireApiUser } from "@/lib/auth/api";
import { deleteAccount } from "@/lib/account/delete-account";
import { confirmsAccountDeletion } from "@/lib/account/confirm-deletion";

/**
 * Mobile-facing counterpart to `settings/privacy/actions.ts`'s
 * `deleteMyAccountAction` -- both call the exact same `deleteAccount()`
 * (lib/account/delete-account.ts), so the real deletion logic (the
 * confirmation check, the audit log entry, the GoTrue Admin API call)
 * exists in exactly one place. Uses `requireApiUser()` so the mobile app
 * can call this directly with a Bearer token, same as every other
 * mobile-facing Route Handler in this app (see ADR 0033). Unlike the
 * Server Action, this route can't `redirect()` -- that's a Next.js
 * Server Action/page concept with no Route Handler equivalent -- so the
 * caller signs itself out and navigates away after a successful
 * `{ ok: true }`. See ADR 0067.
 */
export async function POST(request: Request) {
  const auth = await requireApiUser(request);
  if ("unauthorized" in auth) return auth.unauthorized;
  const { user, supabase } = auth;

  let confirmation = "";
  try {
    const body = await request.json();
    confirmation = typeof body?.confirmation === "string" ? body.confirmation : "";
  } catch {
    return NextResponse.json({ error: "Invalid request body." }, { status: 400 });
  }

  if (!confirmsAccountDeletion(confirmation, user.email)) {
    return NextResponse.json({ error: "Type your account email exactly to confirm." }, { status: 400 });
  }

  const result = await deleteAccount(supabase, user, confirmation);
  if (result.error) {
    return NextResponse.json({ error: result.error }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
