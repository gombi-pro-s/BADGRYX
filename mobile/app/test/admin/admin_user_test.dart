import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/admin/admin_user.dart';

void main() {
  group('AdminUserSearchResult.fromRow', () {
    test('parses a real admin_search_users row shape', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-1',
        'email': 'alice@example.com',
        'username': 'alice',
        'display_name': 'Alice',
        'roles': ['instructor'],
      });
      expect(user.userId, 'user-1');
      expect(user.email, 'alice@example.com');
      expect(user.roles, ['instructor']);
    });

    test('a user with no elevated roles parses an empty roles list', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-2',
        'email': 'bob@example.com',
        'username': null,
        'display_name': null,
        'roles': <String>[],
      });
      expect(user.roles, isEmpty);
    });
  });

  group('AdminUserSearchResult.label', () {
    test('prefers display_name', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-1',
        'email': 'alice@example.com',
        'username': 'alice',
        'display_name': 'Alice',
        'roles': <String>[],
      });
      expect(user.label, 'Alice');
    });

    test('falls back to username when there is no display_name', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-1',
        'email': 'alice@example.com',
        'username': 'alice',
        'display_name': null,
        'roles': <String>[],
      });
      expect(user.label, 'alice');
    });

    test('falls back to email when there is no display_name or username', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-1',
        'email': 'alice@example.com',
        'username': null,
        'display_name': null,
        'roles': <String>[],
      });
      expect(user.label, 'alice@example.com');
    });

    test('falls back to the raw user id as a last resort', () {
      final user = AdminUserSearchResult.fromRow({
        'user_id': 'user-1',
        'email': null,
        'username': null,
        'display_name': null,
        'roles': <String>[],
      });
      expect(user.label, 'user-1');
    });
  });

  test('grantableRoles covers exactly the three real grantable roles', () {
    expect(grantableRoles, ['instructor', 'moderator', 'admin']);
  });

  group('isRoleToggleDisabled', () {
    test('disabled for your own admin role', () {
      expect(isRoleToggleDisabled(role: 'admin', userId: 'me', currentAdminId: 'me'), isTrue);
    });

    test('not disabled for someone else\'s admin role', () {
      expect(isRoleToggleDisabled(role: 'admin', userId: 'someone-else', currentAdminId: 'me'), isFalse);
    });

    test('not disabled for your own instructor or moderator role', () {
      expect(isRoleToggleDisabled(role: 'instructor', userId: 'me', currentAdminId: 'me'), isFalse);
      expect(isRoleToggleDisabled(role: 'moderator', userId: 'me', currentAdminId: 'me'), isFalse);
    });
  });
}
