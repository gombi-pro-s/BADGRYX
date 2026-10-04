import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/reports/report.dart';

void main() {
  group('Report.fromRow', () {
    test('parses a real reports row shape', () {
      final report = Report.fromRow({
        'id': 'report-1',
        'title': 'Acme Corp internal pentest',
        'kind': 'pentest_report',
        'content_markdown': '# Scope\n\n# Findings',
        'updated_at': '2026-01-01T12:00:00.000Z',
      });
      expect(report.id, 'report-1');
      expect(report.title, 'Acme Corp internal pentest');
      expect(report.kind, 'pentest_report');
      expect(report.contentMarkdown, '# Scope\n\n# Findings');
    });

    test('a null content_markdown parses as an empty string', () {
      final report = Report.fromRow({
        'id': 'report-1',
        'title': 'Draft',
        'kind': 'methodology',
        'content_markdown': null,
        'updated_at': '2026-01-01T12:00:00.000Z',
      });
      expect(report.contentMarkdown, '');
    });
  });

  group('reportKindLabel', () {
    test('labels pentest_report', () {
      expect(reportKindLabel('pentest_report'), 'Pentest report');
    });

    test('labels methodology', () {
      expect(reportKindLabel('methodology'), 'Methodology write-up');
    });

    test('falls back to the raw kind for an unknown value', () {
      expect(reportKindLabel('something_new'), 'something_new');
    });
  });
}
