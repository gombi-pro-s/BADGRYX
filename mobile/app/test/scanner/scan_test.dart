import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/scanner/scan.dart';

void main() {
  group('Scan.fromRow', () {
    test('parses a real scans row shape', () {
      final scan = Scan.fromRow({
        'id': 'scan-1',
        'title': 'Scan of 2 files',
        'status': 'completed',
        'total_files': 2,
        'total_findings': 3,
        'findings_by_severity': {'high': 1, 'medium': 2},
        'error_message': null,
        'created_at': '2026-01-01T12:00:00.000Z',
      });
      expect(scan.id, 'scan-1');
      expect(scan.title, 'Scan of 2 files');
      expect(scan.status, 'completed');
      expect(scan.totalFiles, 2);
      expect(scan.totalFindings, 3);
      expect(scan.findingsBySeverity, {'high': 1, 'medium': 2});
      expect(scan.errorMessage, isNull);
    });

    test('a failed scan parses its error_message', () {
      final scan = Scan.fromRow({
        'id': 'scan-2',
        'title': 'Scan of 1 file',
        'status': 'failed',
        'total_files': 1,
        'total_findings': 0,
        'findings_by_severity': <String, dynamic>{},
        'error_message': 'File too large.',
        'created_at': '2026-01-01T12:00:00.000Z',
      });
      expect(scan.status, 'failed');
      expect(scan.errorMessage, 'File too large.');
    });
  });

  group('ScanFinding.fromRow', () {
    test('parses a real scan_findings row shape', () {
      final finding = ScanFinding.fromRow({
        'id': 'finding-1',
        'file_id': 'file-1',
        'rule_id': 'secrets.aws_access_key',
        'category': 'secrets',
        'title': 'Hardcoded AWS access key',
        'severity': 'critical',
        'confidence': 'high',
        'line_start': 10,
        'line_end': 10,
        'evidence': 'const key = "AKIA...";',
        'explanation': 'A real AWS key is embedded in source.',
        'impact': 'Anyone with repo access can use this key.',
        'remediation': 'Move it to a secrets manager.',
        'secure_example': null,
        'verification_status': 'needs_review',
        'ai_enriched': false,
        'status': 'discovered',
      });
      expect(finding.id, 'finding-1');
      expect(finding.severity, 'critical');
      expect(finding.lineStart, 10);
      expect(finding.secureExample, isNull);
      expect(finding.aiEnriched, isFalse);
    });
  });

  test('every severityLabel value is real, human-readable text, not the raw enum value', () {
    for (final severity in severityOrder) {
      final label = severityLabel[severity];
      expect(label, isNotNull, reason: 'missing label for $severity');
      expect(label, isNot(severity), reason: '$severity label should not be the raw value');
    }
  });

  group('aggregatePosture', () {
    Scan scanWith(Map<String, int> severities) => Scan(
      id: 'x',
      title: 'x',
      status: 'completed',
      totalFiles: 1,
      totalFindings: severities.values.fold(0, (a, b) => a + b),
      findingsBySeverity: severities,
      createdAt: DateTime(2026, 1, 1),
    );

    test('sums a single scan straight through', () {
      final posture = aggregatePosture([scanWith({'high': 2, 'low': 1})]);
      expect(posture, {'high': 2, 'low': 1});
    });

    test('sums across multiple scans, combining shared severities', () {
      final posture = aggregatePosture([
        scanWith({'high': 2, 'low': 1}),
        scanWith({'high': 1, 'critical': 3}),
      ]);
      expect(posture, {'high': 3, 'low': 1, 'critical': 3});
    });

    test('an empty scan list has an empty posture', () {
      expect(aggregatePosture([]), isEmpty);
    });
  });

  group('formatScanTimestamp', () {
    test('drops fractional seconds', () {
      final formatted = formatScanTimestamp(DateTime(2026, 1, 1, 12, 30, 45, 123));
      expect(formatted, isNot(contains('.')));
      expect(formatted, startsWith('2026-01-01 12:30:45'));
    });
  });

  group('legalStatusTransitions', () {
    const allStatuses = [
      'discovered',
      'remediation_required',
      'fix_applied',
      'retested',
      'verified_fixed',
      'false_positive',
      'wont_fix',
    ];

    test('every status has an entry, and every listed status is itself a real status', () {
      for (final status in allStatuses) {
        final nextStatuses = legalStatusTransitions[status];
        expect(nextStatuses, isNotNull, reason: 'missing transitions for $status');
        for (final next in nextStatuses!) {
          expect(allStatuses, contains(next), reason: '$status lists unknown next status $next');
        }
      }
    });

    test('every status reachable by a transition has an action label and a status label', () {
      for (final nextStatuses in legalStatusTransitions.values) {
        for (final next in nextStatuses) {
          expect(statusActionLabel[next], isNotNull, reason: 'missing action label for $next');
          expect(findingStatusLabel[next], isNotNull, reason: 'missing status label for $next');
        }
      }
    });

    test('terminal-sounding statuses can still be walked back to remediation_required', () {
      expect(legalStatusTransitions['false_positive'], contains('remediation_required'));
      expect(legalStatusTransitions['wont_fix'], contains('remediation_required'));
      expect(legalStatusTransitions['verified_fixed'], contains('remediation_required'));
    });
  });

  group('buildScanRequestBody', () {
    test('uses pasted_snippet with the one pasted file when no files are picked', () {
      final body = buildScanRequestBody(pickedFiles: [], pastedFilename: 'snippet.js', pastedCode: 'const x = 1;');
      expect(body['targetType'], 'pasted_snippet');
      expect(body['files'], [
        {'filename': 'snippet.js', 'content': 'const x = 1;'},
      ]);
      expect(body.containsKey('title'), isFalse);
    });

    test('uses uploaded_files with every picked file when one or more are picked', () {
      final body = buildScanRequestBody(
        pickedFiles: [
          ScanUploadFile(filename: 'a.js', content: 'const a = 1;'),
          ScanUploadFile(filename: 'b.py', content: 'b = 2'),
        ],
        pastedFilename: 'snippet.js',
        pastedCode: 'ignored because files were picked',
      );
      expect(body['targetType'], 'uploaded_files');
      expect(body['files'], [
        {'filename': 'a.js', 'content': 'const a = 1;'},
        {'filename': 'b.py', 'content': 'b = 2'},
      ]);
    });

    test('includes a non-empty title', () {
      final body = buildScanRequestBody(
        title: 'My scan',
        pickedFiles: [],
        pastedFilename: 'snippet.js',
        pastedCode: 'const x = 1;',
      );
      expect(body['title'], 'My scan');
    });

    test('omits an empty or null title', () {
      final withEmpty = buildScanRequestBody(
        title: '',
        pickedFiles: [],
        pastedFilename: 'snippet.js',
        pastedCode: 'const x = 1;',
      );
      final withNull = buildScanRequestBody(pickedFiles: [], pastedFilename: 'snippet.js', pastedCode: 'const x = 1;');
      expect(withEmpty.containsKey('title'), isFalse);
      expect(withNull.containsKey('title'), isFalse);
    });
  });
}
