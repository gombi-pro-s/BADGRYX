/// One row of admin_search_users()'s result -- the one admin-only,
/// narrowly-scoped read across the auth.users boundary (email/username/
/// display_name/current roles, nothing else). See
/// 20260922000016_admin_user_role_management.sql.
class AdminUserSearchResult {
  AdminUserSearchResult({
    required this.userId,
    required this.email,
    required this.username,
    required this.displayName,
    required this.roles,
  });

  final String userId;
  final String? email;
  final String? username;
  final String? displayName;
  final List<String> roles;

  factory AdminUserSearchResult.fromRow(Map<String, dynamic> row) {
    return AdminUserSearchResult(
      userId: row['user_id'] as String,
      email: row['email'] as String?,
      username: row['username'] as String?,
      displayName: row['display_name'] as String?,
      roles: (row['roles'] as List).cast<String>(),
    );
  }

  /// Mirrors user-search.tsx's `user.display_name ?? user.username ?? user.email ?? user.user_id`.
  String get label => displayName ?? username ?? email ?? userId;
}

/// Mirrors user-search.tsx's GRANTABLE_ROLES exactly -- 'user' is every
/// real account's implicit baseline (handle_new_user()'s trigger, never
/// a toggle), not something to grant/revoke here.
const List<String> grantableRoles = ['instructor', 'moderator', 'admin'];

/// Mirrors user-search.tsx's inline `disabled={role === "admin" && user.user_id === currentAdminId}`:
/// revoke_platform_role() itself refuses this server-side regardless, but
/// the UI disables the toggle rather than letting a tap round-trip into
/// an error it already knows is coming.
bool isRoleToggleDisabled({required String role, required String userId, required String currentAdminId}) {
  return role == 'admin' && userId == currentAdminId;
}
