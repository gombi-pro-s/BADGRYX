import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/ctf/ctf_challenge.dart';

void main() {
  group('CtfChallenge.fromRow', () {
    test('parses a real ctf_challenges_public row shape', () {
      final challenge = CtfChallenge.fromRow({
        'id': 'abc-123',
        'title': 'SQL Injection: Login Bypass',
        'description': 'Bypass the login form.',
        'category': 'web',
        'difficulty': 'easy',
        'points': 100,
      });
      expect(challenge.id, 'abc-123');
      expect(challenge.title, 'SQL Injection: Login Bypass');
      expect(challenge.description, 'Bypass the login form.');
      expect(challenge.category, 'web');
      expect(challenge.difficulty, 'easy');
      expect(challenge.points, 100);
    });

    test('a null description is preserved as null, not coerced to empty string', () {
      final challenge = CtfChallenge.fromRow({
        'id': 'abc-123',
        'title': 'No description',
        'description': null,
        'category': 'web',
        'difficulty': 'easy',
        'points': 50,
      });
      expect(challenge.description, isNull);
    });
  });

  group('CtfSubmissionResult.fromRow', () {
    test('parses a correct submission row', () {
      final result = CtfSubmissionResult.fromRow({'correct': true, 'points_awarded': 150});
      expect(result.correct, isTrue);
      expect(result.pointsAwarded, 150);
    });

    test('parses an incorrect submission row (0 points)', () {
      final result = CtfSubmissionResult.fromRow({'correct': false, 'points_awarded': 0});
      expect(result.correct, isFalse);
      expect(result.pointsAwarded, 0);
    });
  });
}
