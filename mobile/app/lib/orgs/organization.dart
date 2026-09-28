class Organization {
  Organization({required this.id, required this.slug, required this.name});

  final String id;
  final String slug;
  final String name;

  factory Organization.fromRow(Map<String, dynamic> row) {
    return Organization(id: row['id'] as String, slug: row['slug'] as String, name: row['name'] as String);
  }
}

class OrgMembership {
  OrgMembership({required this.role, required this.organization});

  final String role;
  final Organization organization;
}

class OrganizationMember {
  OrganizationMember({required this.id, required this.userId, required this.role, required this.joinedAt});

  final String id;
  final String userId;
  final String role;
  final DateTime joinedAt;

  factory OrganizationMember.fromRow(Map<String, dynamic> row) {
    return OrganizationMember(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      role: row['role'] as String,
      joinedAt: DateTime.parse(row['joined_at'] as String),
    );
  }
}

class OrganizationInvitation {
  OrganizationInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
  });

  final String id;
  final String email;
  final String role;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  factory OrganizationInvitation.fromRow(Map<String, dynamic> row) {
    return OrganizationInvitation(
      id: row['id'] as String,
      email: row['email'] as String,
      role: row['role'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      acceptedAt: row['accepted_at'] != null ? DateTime.parse(row['accepted_at'] as String) : null,
      revokedAt: row['revoked_at'] != null ? DateTime.parse(row['revoked_at'] as String) : null,
    );
  }
}

/// Mirrors apps/web's ORG roles exactly (types/database.ts's OrgRole).
const List<String> allOrgRoles = ['member', 'instructor', 'team_owner', 'org_admin'];

/// Mirrors orgs/[orgId]/page.tsx's ADMIN_ROLES.
const List<String> orgAdminRoles = ['team_owner', 'org_admin'];

/// Mirrors orgs/[orgId]/page.tsx's INSTRUCTOR_ROLES.
const List<String> orgInstructorRoles = ['instructor', 'team_owner', 'org_admin'];

bool isOrgAdminRole(String role) => orgAdminRoles.contains(role);

bool isOrgInstructorRole(String role) => orgInstructorRoles.contains(role);

/// Mirrors the `role.replace("_", " ")` calls used throughout the web
/// org pages (member-actions.tsx, invite-form.tsx, orgs/page.tsx).
String formatOrgRole(String role) => role.replaceAll('_', ' ');

/// Mirrors orgs/[orgId]/page.tsx's inline invitation-status ternary
/// exactly: revoked wins over accepted, accepted wins over expiry.
String invitationStatus(OrganizationInvitation invitation, DateTime now) {
  if (invitation.revokedAt != null) return 'Revoked';
  if (invitation.acceptedAt != null) return 'Accepted';
  if (invitation.expiresAt.isBefore(now)) return 'Expired';
  return 'Pending';
}
