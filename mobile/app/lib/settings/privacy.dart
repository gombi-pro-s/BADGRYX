/// Direct port of `lib/account/confirm-deletion.ts`'s
/// `confirmsAccountDeletion()`: does the typed string match the
/// account's own email, case-insensitively and trimmed? Checked here
/// client-side first (so a mismatch never even reaches the network),
/// and again server-side by `POST /api/account/delete` -- the same
/// belt-and-suspenders pattern every other client-validated form in
/// this app uses, since the real boundary is always server-side. See
/// ADR 0067.
bool confirmsAccountDeletion(String confirmation, String? email) {
  if (email == null || email.isEmpty) return false;
  return confirmation.trim().toLowerCase() == email.toLowerCase();
}
