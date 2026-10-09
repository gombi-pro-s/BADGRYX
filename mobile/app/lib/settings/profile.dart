/// Direct port of `settings/actions.ts`'s `profileSchema` (a zod object
/// schema) and its field order -- zod's `safeParse` reports
/// `issues[0]`, the first field (in schema-declaration order:
/// display_name, username, bio, timezone) that fails, so this checks
/// in that same order and returns the first failure's message, or null
/// when every field is valid.
String? validateProfileUpdate({
  required String displayName,
  required String username,
  required String bio,
  required String timezone,
}) {
  // The three length-exceeded messages below are zod v4's own default
  // "too_big" wording (verified by running the real schema from
  // settings/actions.ts through node), not an invented string -- these
  // three fields have no custom zod message, unlike username's. In
  // practice they're defensive only: the matching TextField's
  // maxLength already stops a user from typing past the limit.
  final trimmedDisplayName = displayName.trim();
  if (trimmedDisplayName.isEmpty) return 'Display name is required.';
  if (trimmedDisplayName.length > 80) return 'Too big: expected string to have <=80 characters';

  final trimmedUsername = username.trim();
  if (trimmedUsername.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_-]{3,32}$').hasMatch(trimmedUsername)) {
    return '3-32 characters: letters, numbers, - or _.';
  }

  if (bio.trim().length > 280) return 'Too big: expected string to have <=280 characters';

  if (timezone.trim().length > 64) return 'Too big: expected string to have <=64 characters';

  return null;
}

/// Mirrors `updateProfileAction`'s own row shape exactly: an empty
/// `username`/`bio` is stored as `null`, never an empty string.
Map<String, dynamic> buildProfileUpdateRow({
  required String displayName,
  required String username,
  required String bio,
  required String timezone,
}) {
  final trimmedUsername = username.trim();
  final trimmedBio = bio.trim();
  return {
    'display_name': displayName.trim(),
    'username': trimmedUsername.isEmpty ? null : trimmedUsername,
    'bio': trimmedBio.isEmpty ? null : trimmedBio,
    'timezone': timezone.trim(),
  };
}
