import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/admin/admin_ctf.dart';

void main() {
  group('isValidCtfSlug', () {
    test('accepts lowercase letters, digits, hyphens, 3-64 chars', () {
      expect(isValidCtfSlug('web-sqli-1'), true);
      expect(isValidCtfSlug('abc'), true);
    });

    test('rejects uppercase, spaces, and too-short slugs', () {
      expect(isValidCtfSlug('Web-Sqli'), false);
      expect(isValidCtfSlug('a b'), false);
      expect(isValidCtfSlug('ab'), false);
    });
  });

  group('hashCtfFlag', () {
    test('matches the known SHA-256 hex digest of a fixed plaintext', () {
      expect(hashCtfFlag('flag{test}'), 'd26b71303eebb857561a2e123debd6006bbe437b30a0fb04d25810c568896536');
    });

    test('matches a second known digest', () {
      expect(hashCtfFlag('abcd'), '88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589');
    });

    test('is deterministic', () {
      expect(hashCtfFlag('same-input'), hashCtfFlag('same-input'));
    });
  });

  group('ctfEventTimeRangeError', () {
    test('null when either side is absent', () {
      expect(ctfEventTimeRangeError(null, null), null);
      expect(ctfEventTimeRangeError(DateTime(2026, 1, 1), null), null);
      expect(ctfEventTimeRangeError(null, DateTime(2026, 1, 1)), null);
    });

    test('null when ends_at is after starts_at', () {
      expect(ctfEventTimeRangeError(DateTime(2026, 1, 1), DateTime(2026, 1, 2)), null);
    });

    test('an error when ends_at is not after starts_at', () {
      const message = 'End time must be after the start time.';
      expect(ctfEventTimeRangeError(DateTime(2026, 1, 2), DateTime(2026, 1, 1)), message);
      expect(ctfEventTimeRangeError(DateTime(2026, 1, 1), DateTime(2026, 1, 1)), message);
    });
  });

  group('AdminCtfChallenge.fromRow', () {
    test('parses a real ctf_challenges row shape', () {
      final challenge = AdminCtfChallenge.fromRow({
        'id': 'c1',
        'slug': 'web-sqli-1',
        'title': 'SQLi 101',
        'description': 'Find the injection.',
        'category': 'web',
        'difficulty': 'easy',
        'points': 100,
        'published': true,
        'event_id': 'e1',
      });
      expect(challenge.id, 'c1');
      expect(challenge.eventId, 'e1');
      expect(challenge.published, true);
      expect(challenge.minPoints, isNull);
    });

    test('parses a real min_points value when the row has one', () {
      final challenge = AdminCtfChallenge.fromRow({
        'id': 'c2',
        'slug': 'web-sqli-2',
        'title': 'SQLi 102',
        'description': null,
        'category': 'web',
        'difficulty': 'medium',
        'points': 200,
        'min_points': 50,
        'published': false,
        'event_id': null,
      });
      expect(challenge.minPoints, 50);
    });
  });

  group('AdminCtfEvent.fromRow', () {
    test('parses starts_at/ends_at as DateTime, null when absent', () {
      final event = AdminCtfEvent.fromRow({
        'id': 'e1',
        'slug': 'spring-ctf',
        'title': 'Spring CTF',
        'description': null,
        'scoring_type': 'static',
        'starts_at': '2026-01-01T00:00:00.000Z',
        'ends_at': null,
        'published': false,
      });
      expect(event.startsAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
      expect(event.endsAt, null);
    });
  });
}
