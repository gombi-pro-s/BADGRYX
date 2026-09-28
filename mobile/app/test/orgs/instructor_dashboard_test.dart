import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/orgs/instructor_dashboard.dart';

void main() {
  group('computeMemberStats', () {
    test('aggregates every stat for a single member from their own rows only', () {
      final stats = computeMemberStats(
        members: [
          {'user_id': 'alice', 'role': 'member'},
        ],
        profiles: [
          {'id': 'alice', 'display_name': 'Alice', 'username': 'alice123'},
        ],
        skillStates: [
          {'user_id': 'alice', 'state': 'MASTERED'},
          {'user_id': 'alice', 'state': 'DEMONSTRATED'},
          {'user_id': 'alice', 'state': 'LEARNING'},
          {'user_id': 'alice', 'state': 'NOT_STARTED'},
        ],
        labProgress: [
          {'user_id': 'alice', 'status': 'completed'},
          {'user_id': 'alice', 'status': 'in_progress'},
        ],
        quizAttempts: [
          {'user_id': 'alice', 'passed': true},
          {'user_id': 'alice', 'passed': false},
        ],
        ctfSubmissions: [
          {'user_id': 'alice', 'correct': true},
        ],
        investigationSubmissions: [
          {'user_id': 'alice', 'passed': true},
          {'user_id': 'alice', 'passed': true},
        ],
      );

      expect(stats, hasLength(1));
      final alice = stats.first;
      expect(alice.name, 'Alice');
      expect(alice.masteredOrDemonstrated, 2);
      expect(alice.inProgress, 1);
      expect(alice.labsCompleted, 1);
      expect(alice.quizzesPassed, 1);
      expect(alice.ctfSolved, 1);
      expect(alice.investigationsPassed, 2);
    });

    test('keeps each member scoped to only their own rows, not another member\'s', () {
      final stats = computeMemberStats(
        members: [
          {'user_id': 'alice', 'role': 'member'},
          {'user_id': 'bob', 'role': 'instructor'},
        ],
        profiles: [
          {'id': 'alice', 'display_name': 'Alice', 'username': null},
          {'id': 'bob', 'display_name': 'Bob', 'username': null},
        ],
        skillStates: [
          {'user_id': 'alice', 'state': 'MASTERED'},
          {'user_id': 'bob', 'state': 'MASTERED'},
          {'user_id': 'bob', 'state': 'MASTERED'},
        ],
        labProgress: [],
        quizAttempts: [],
        ctfSubmissions: [],
        investigationSubmissions: [],
      );

      final alice = stats.firstWhere((s) => s.userId == 'alice');
      final bob = stats.firstWhere((s) => s.userId == 'bob');
      expect(alice.masteredOrDemonstrated, 1);
      expect(bob.masteredOrDemonstrated, 2);
    });

    test('falls back to username, then user id, when display_name is missing', () {
      final withUsername = computeMemberStats(
        members: [
          {'user_id': 'carol', 'role': 'member'},
        ],
        profiles: [
          {'id': 'carol', 'display_name': null, 'username': 'carol_c'},
        ],
        skillStates: [],
        labProgress: [],
        quizAttempts: [],
        ctfSubmissions: [],
        investigationSubmissions: [],
      );
      expect(withUsername.first.name, 'carol_c');

      final withNeither = computeMemberStats(
        members: [
          {'user_id': 'dave', 'role': 'member'},
        ],
        profiles: [],
        skillStates: [],
        labProgress: [],
        quizAttempts: [],
        ctfSubmissions: [],
        investigationSubmissions: [],
      );
      expect(withNeither.first.name, 'dave');
    });

    test('a member with no rows anywhere gets all-zero stats, not an error', () {
      final stats = computeMemberStats(
        members: [
          {'user_id': 'eve', 'role': 'member'},
        ],
        profiles: [
          {'id': 'eve', 'display_name': 'Eve', 'username': null},
        ],
        skillStates: [],
        labProgress: [],
        quizAttempts: [],
        ctfSubmissions: [],
        investigationSubmissions: [],
      );
      final eve = stats.first;
      expect(eve.masteredOrDemonstrated, 0);
      expect(eve.inProgress, 0);
      expect(eve.labsCompleted, 0);
      expect(eve.quizzesPassed, 0);
      expect(eve.ctfSolved, 0);
      expect(eve.investigationsPassed, 0);
    });

    test('returns an empty list for an org with no members', () {
      final stats = computeMemberStats(
        members: [],
        profiles: [],
        skillStates: [],
        labProgress: [],
        quizAttempts: [],
        ctfSubmissions: [],
        investigationSubmissions: [],
      );
      expect(stats, isEmpty);
    });
  });
}
