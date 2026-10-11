import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/auth/validation.dart';

void main() {
  group('validateEmail', () {
    test('accepts a real-looking email', () {
      expect(validateEmail('user@example.com'), isNull);
    });

    test('rejects a string with no @', () {
      expect(validateEmail('not-an-email'), isNotNull);
    });

    test('rejects a string with no domain', () {
      expect(validateEmail('user@'), isNotNull);
    });

    test('rejects an empty string', () {
      expect(validateEmail(''), isNotNull);
    });
  });

  group('validatePassword', () {
    test('accepts a password meeting every rule', () {
      expect(validatePassword('Abcdefgh1234'), isNull);
    });

    test('rejects a password shorter than 12 characters', () {
      expect(validatePassword('Ab1defghi'), 'Password must be at least 12 characters.');
    });

    test('rejects a password with no uppercase letter', () {
      expect(validatePassword('abcdefgh1234'), 'Password must include an uppercase letter.');
    });

    test('rejects a password with no lowercase letter', () {
      expect(validatePassword('ABCDEFGH1234'), 'Password must include a lowercase letter.');
    });

    test('rejects a password with no digit', () {
      expect(validatePassword('Abcdefghijkl'), 'Password must include a number.');
    });
  });

  group('isValidTotpCode', () {
    test('accepts a 6-digit code', () {
      expect(isValidTotpCode('123456'), isTrue);
    });

    test('accepts a 6-digit code with surrounding whitespace', () {
      expect(isValidTotpCode('  123456  '), isTrue);
    });

    test('rejects fewer than 6 digits', () {
      expect(isValidTotpCode('12345'), isFalse);
    });

    test('rejects more than 6 digits', () {
      expect(isValidTotpCode('1234567'), isFalse);
    });

    test('rejects non-digit characters', () {
      expect(isValidTotpCode('12345a'), isFalse);
    });

    test('rejects an empty string', () {
      expect(isValidTotpCode(''), isFalse);
    });
  });
}
