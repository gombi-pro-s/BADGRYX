import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/admin/admin_path.dart';

void main() {
  group('isValidContentSlug', () {
    test('accepts lowercase letters, digits, hyphens, 3-64 chars', () {
      expect(isValidContentSlug('web-app-security'), true);
    });

    test('rejects uppercase and too-short slugs', () {
      expect(isValidContentSlug('Web-App'), false);
      expect(isValidContentSlug('ab'), false);
    });
  });

  group('AdminLearningPath.fromRow', () {
    test('parses a real learning_paths row shape', () {
      final path = AdminLearningPath.fromRow({
        'id': 'p1',
        'slug': 'web-app-security',
        'title': 'Web App Security',
        'description': 'OWASP Top 10 and beyond.',
        'published': true,
      });
      expect(path.id, 'p1');
      expect(path.description, 'OWASP Top 10 and beyond.');
      expect(path.published, true);
    });
  });

  group('AdminModuleSummary.fromRow and AdminLessonSummary.fromRow', () {
    test('parse the minimal row shapes used in each list', () {
      final module = AdminModuleSummary.fromRow({'id': 'm1', 'title': 'SQL Injection', 'published': false});
      expect(module.title, 'SQL Injection');
      expect(module.published, false);

      final lesson = AdminLessonSummary.fromRow({'id': 'l1', 'title': 'Introduction', 'published': true});
      expect(lesson.title, 'Introduction');
      expect(lesson.published, true);
    });
  });

  group('AdminLessonDetail.fromRow', () {
    test('parses a real lessons row shape', () {
      final lesson = AdminLessonDetail.fromRow({
        'id': 'l1',
        'slug': 'introduction',
        'title': 'Introduction',
        'summary': 'A quick overview.',
        'content_markdown': '# Intro',
        'estimated_minutes': 10,
        'published': false,
      });
      expect(lesson.contentMarkdown, '# Intro');
      expect(lesson.estimatedMinutes, 10);
      expect(lesson.published, false);
    });

    test('a null summary parses as null, not an empty string', () {
      final lesson = AdminLessonDetail.fromRow({
        'id': 'l1',
        'slug': 'introduction',
        'title': 'Introduction',
        'summary': null,
        'content_markdown': '# Intro',
        'estimated_minutes': 10,
        'published': false,
      });
      expect(lesson.summary, null);
    });
  });
}
