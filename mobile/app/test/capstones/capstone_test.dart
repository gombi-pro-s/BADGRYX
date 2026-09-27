import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/capstones/capstone.dart';

void main() {
  group('Capstone.fromRow', () {
    test('parses a real capstones row shape', () {
      final capstone = Capstone.fromRow({
        'id': 'c1',
        'title': 'SQL Injection: Full Pentest Report',
        'description': 'Find and report every injection point.',
        'report_required': true,
      });
      expect(capstone.id, 'c1');
      expect(capstone.reportRequired, isTrue);
    });
  });

  group('CapstoneSubmission.fromRow', () {
    test('parses a real capstone_submissions row shape', () {
      final submission = CapstoneSubmission.fromRow({
        'status': 'passed',
        'reviewer_notes': 'Great work.',
        'submitted_at': '2026-01-15T10:00:00Z',
      });
      expect(submission.status, 'passed');
      expect(submission.reviewerNotes, 'Great work.');
    });

    test('a submission with no reviewer notes yet parses as null', () {
      final submission = CapstoneSubmission.fromRow({
        'status': 'submitted',
        'reviewer_notes': null,
        'submitted_at': '2026-01-15T10:00:00Z',
      });
      expect(submission.reviewerNotes, isNull);
    });
  });

  group('latestStatusByCapstone', () {
    test('takes the first (newest, since rows arrive newest-first) submission per capstone', () {
      final latest = latestStatusByCapstone([
        {'capstone_id': 'c1', 'status': 'passed', 'submitted_at': '2026-02-01T00:00:00Z'},
        {'capstone_id': 'c1', 'status': 'needs_revision', 'submitted_at': '2026-01-01T00:00:00Z'},
      ]);
      expect(latest['c1'], 'passed');
    });

    test('tracks separate latest statuses for separate capstones', () {
      final latest = latestStatusByCapstone([
        {'capstone_id': 'c1', 'status': 'passed', 'submitted_at': '2026-02-01T00:00:00Z'},
        {'capstone_id': 'c2', 'status': 'under_review', 'submitted_at': '2026-02-01T00:00:00Z'},
      ]);
      expect(latest['c1'], 'passed');
      expect(latest['c2'], 'under_review');
    });

    test('a capstone with no submissions has no entry', () {
      expect(latestStatusByCapstone([])['c1'], isNull);
    });
  });

  test('every capstoneStatusLabel value is real, human-readable text, not the raw enum', () {
    for (final status in ['submitted', 'under_review', 'passed', 'needs_revision']) {
      expect(capstoneStatusLabel[status], isNot(equals(status)));
    }
  });
}
