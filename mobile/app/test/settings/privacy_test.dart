import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/settings/privacy.dart';

void main() {
  group('confirmsAccountDeletion', () {
    test('matches the exact email', () {
      expect(confirmsAccountDeletion('user@example.com', 'user@example.com'), isTrue);
    });

    test('is case-insensitive', () {
      expect(confirmsAccountDeletion('USER@EXAMPLE.COM', 'user@example.com'), isTrue);
    });

    test('ignores leading/trailing whitespace in the typed confirmation', () {
      expect(confirmsAccountDeletion('  user@example.com  ', 'user@example.com'), isTrue);
    });

    test('rejects a mismatched email', () {
      expect(confirmsAccountDeletion('someone-else@example.com', 'user@example.com'), isFalse);
    });

    test('rejects an empty confirmation', () {
      expect(confirmsAccountDeletion('', 'user@example.com'), isFalse);
    });

    test('rejects when the account has no email at all', () {
      expect(confirmsAccountDeletion('user@example.com', null), isFalse);
      expect(confirmsAccountDeletion('user@example.com', ''), isFalse);
    });
  });
}
