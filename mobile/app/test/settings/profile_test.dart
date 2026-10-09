import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/settings/profile.dart';

void main() {
  group('validateProfileUpdate', () {
    test('accepts a fully valid profile', () {
      expect(
        validateProfileUpdate(displayName: 'Ada Lovelace', username: 'ada_l', bio: 'Pentester.', timezone: 'UTC'),
        isNull,
      );
    });

    test('accepts an empty username and empty bio (both optional)', () {
      expect(
        validateProfileUpdate(displayName: 'Ada', username: '', bio: '', timezone: 'UTC'),
        isNull,
      );
    });

    test('rejects a blank display name', () {
      expect(
        validateProfileUpdate(displayName: '   ', username: '', bio: '', timezone: 'UTC'),
        'Display name is required.',
      );
    });

    test('rejects a display name over 80 characters', () {
      expect(
        validateProfileUpdate(displayName: 'a' * 81, username: '', bio: '', timezone: 'UTC'),
        'Too big: expected string to have <=80 characters',
      );
    });

    test('rejects a username shorter than 3 characters', () {
      expect(
        validateProfileUpdate(displayName: 'Ada', username: 'ab', bio: '', timezone: 'UTC'),
        '3-32 characters: letters, numbers, - or _.',
      );
    });

    test('rejects a username with an invalid character', () {
      expect(
        validateProfileUpdate(displayName: 'Ada', username: 'ada lovelace', bio: '', timezone: 'UTC'),
        '3-32 characters: letters, numbers, - or _.',
      );
    });

    test('accepts a username at the boundary lengths (3 and 32)', () {
      expect(validateProfileUpdate(displayName: 'Ada', username: 'abc', bio: '', timezone: 'UTC'), isNull);
      expect(validateProfileUpdate(displayName: 'Ada', username: 'a' * 32, bio: '', timezone: 'UTC'), isNull);
    });

    test('rejects a bio over 280 characters', () {
      expect(
        validateProfileUpdate(displayName: 'Ada', username: '', bio: 'a' * 281, timezone: 'UTC'),
        'Too big: expected string to have <=280 characters',
      );
    });

    test('rejects a timezone over 64 characters', () {
      expect(
        validateProfileUpdate(displayName: 'Ada', username: '', bio: '', timezone: 'a' * 65),
        'Too big: expected string to have <=64 characters',
      );
    });

    test('checks fields in schema order: a blank display name wins over an invalid username', () {
      expect(
        validateProfileUpdate(displayName: '', username: 'x', bio: '', timezone: 'UTC'),
        'Display name is required.',
      );
    });
  });

  group('buildProfileUpdateRow', () {
    test('trims every field', () {
      final row = buildProfileUpdateRow(
        displayName: '  Ada  ',
        username: '  ada_l  ',
        bio: '  Pentester.  ',
        timezone: '  UTC  ',
      );
      expect(row, {'display_name': 'Ada', 'username': 'ada_l', 'bio': 'Pentester.', 'timezone': 'UTC'});
    });

    test('stores an empty username as null, not an empty string', () {
      final row = buildProfileUpdateRow(displayName: 'Ada', username: '', bio: '', timezone: 'UTC');
      expect(row['username'], isNull);
    });

    test('stores an empty bio as null, not an empty string', () {
      final row = buildProfileUpdateRow(displayName: 'Ada', username: '', bio: '   ', timezone: 'UTC');
      expect(row['bio'], isNull);
    });
  });
}
