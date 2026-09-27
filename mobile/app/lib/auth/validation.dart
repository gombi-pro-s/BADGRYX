/// Pure validators, no I/O -- mirrors apps/web's lib/auth/validation.ts
/// exactly (same email check, same password policy) so both clients
/// enforce the identical rule before ever calling Supabase Auth.
library;

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Returns null when valid, otherwise a user-facing error message. Takes a
/// nullable String so it can be used directly as a Flutter form-field
/// validator without a wrapper closure at every call site.
String? validateEmail(String? email) {
  if (email == null || !_emailPattern.hasMatch(email)) return 'Enter a valid email address.';
  return null;
}

/// Same policy as apps/web's passwordSchema: at least 12 characters, one
/// uppercase, one lowercase, one digit.
String? validatePassword(String? password) {
  final value = password ?? '';
  if (value.length < 12) return 'Password must be at least 12 characters.';
  if (!value.contains(RegExp(r'[A-Z]'))) return 'Password must include an uppercase letter.';
  if (!value.contains(RegExp(r'[a-z]'))) return 'Password must include a lowercase letter.';
  if (!value.contains(RegExp(r'[0-9]'))) return 'Password must include a number.';
  return null;
}
