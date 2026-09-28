import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/orgs/organization.dart';

void main() {
  group('Organization.fromRow', () {
    test('parses a real organizations row shape', () {
      final org = Organization.fromRow({'id': 'org-1', 'slug': 'acme-security', 'name': 'Acme Security'});
      expect(org.id, 'org-1');
      expect(org.slug, 'acme-security');
      expect(org.name, 'Acme Security');
    });
  });

  group('OrganizationMember.fromRow', () {
    test('parses a real organization_members row shape', () {
      final member = OrganizationMember.fromRow({
        'id': 'member-1',
        'user_id': 'user-1',
        'role': 'instructor',
        'joined_at': '2026-01-01T00:00:00.000Z',
      });
      expect(member.role, 'instructor');
      expect(member.userId, 'user-1');
    });
  });

  group('OrganizationInvitation.fromRow', () {
    test('parses a real organization_invitations row shape', () {
      final invitation = OrganizationInvitation.fromRow({
        'id': 'inv-1',
        'email': 'person@example.com',
        'role': 'member',
        'expires_at': '2026-02-01T00:00:00.000Z',
        'accepted_at': null,
        'revoked_at': null,
      });
      expect(invitation.email, 'person@example.com');
      expect(invitation.acceptedAt, isNull);
      expect(invitation.revokedAt, isNull);
    });
  });

  group('isOrgAdminRole', () {
    test('true for team_owner and org_admin', () {
      expect(isOrgAdminRole('team_owner'), isTrue);
      expect(isOrgAdminRole('org_admin'), isTrue);
    });

    test('false for member and instructor', () {
      expect(isOrgAdminRole('member'), isFalse);
      expect(isOrgAdminRole('instructor'), isFalse);
    });
  });

  group('isOrgInstructorRole', () {
    test('true for instructor, team_owner, and org_admin', () {
      expect(isOrgInstructorRole('instructor'), isTrue);
      expect(isOrgInstructorRole('team_owner'), isTrue);
      expect(isOrgInstructorRole('org_admin'), isTrue);
    });

    test('false for member', () {
      expect(isOrgInstructorRole('member'), isFalse);
    });
  });

  test('formatOrgRole replaces underscores with spaces', () {
    expect(formatOrgRole('team_owner'), 'team owner');
    expect(formatOrgRole('member'), 'member');
  });

  group('invitationStatus', () {
    final now = DateTime(2026, 1, 15);

    test('revoked wins over everything else', () {
      final invitation = OrganizationInvitation(
        id: 'i',
        email: 'e',
        role: 'member',
        expiresAt: DateTime(2026, 2, 1),
        acceptedAt: DateTime(2026, 1, 10),
        revokedAt: DateTime(2026, 1, 12),
      );
      expect(invitationStatus(invitation, now), 'Revoked');
    });

    test('accepted wins over expiry when not revoked', () {
      final invitation = OrganizationInvitation(
        id: 'i',
        email: 'e',
        role: 'member',
        expiresAt: DateTime(2026, 1, 1),
        acceptedAt: DateTime(2025, 12, 20),
      );
      expect(invitationStatus(invitation, now), 'Accepted');
    });

    test('expired when past expiry with no acceptance or revocation', () {
      final invitation = OrganizationInvitation(id: 'i', email: 'e', role: 'member', expiresAt: DateTime(2026, 1, 1));
      expect(invitationStatus(invitation, now), 'Expired');
    });

    test('pending when none of the above apply', () {
      final invitation = OrganizationInvitation(id: 'i', email: 'e', role: 'member', expiresAt: DateTime(2026, 2, 1));
      expect(invitationStatus(invitation, now), 'Pending');
    });
  });
}
