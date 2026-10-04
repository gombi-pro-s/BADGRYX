import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/auth/roles.dart';

void main() {
  group('isStaffRole', () {
    test('true when the user holds the admin role', () {
      expect(isStaffRole(['user', 'admin']), isTrue);
    });

    test('true when the user holds the moderator role', () {
      expect(isStaffRole(['user', 'moderator']), isTrue);
    });

    test('false for a plain user with no elevated role', () {
      expect(isStaffRole(['user']), isFalse);
    });

    test('false for an org-scoped role alone -- platform staff is a separate system', () {
      expect(isStaffRole(['instructor']), isFalse);
    });

    test('false with no roles at all', () {
      expect(isStaffRole([]), isFalse);
    });
  });
}
