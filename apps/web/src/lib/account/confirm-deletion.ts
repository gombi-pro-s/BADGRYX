// Pure logic, no "server-only" -- mirrors announcement-translation.ts's
// own reasoning: a future client-side use (an inline check before the
// form even submits) shouldn't need a server-only import to reuse this.

/**
 * Does the typed string match the account's own email, case-
 * insensitively and trimmed? Shared by `deleteAccount()`
 * (lib/account/delete-account.ts) and its two callers -- the web
 * Server Action and the mobile-facing `/api/account/delete` Route
 * Handler -- so a mismatch is rejected identically whichever client
 * asked. See ADR 0067.
 */
export function confirmsAccountDeletion(confirmation: string, email: string | null | undefined): boolean {
  if (!email) return false;
  return confirmation.trim().toLowerCase() === email.toLowerCase();
}
