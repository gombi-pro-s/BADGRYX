import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/admin/admin_lab.dart';

void main() {
  group('isValidLabSlug', () {
    test('accepts lowercase letters, digits, hyphens, 3-64 chars', () {
      expect(isValidLabSlug('sqli-101'), true);
    });

    test('rejects uppercase and too-short slugs', () {
      expect(isValidLabSlug('SQLi-101'), false);
      expect(isValidLabSlug('ab'), false);
    });
  });

  group('AdminLab.fromRow', () {
    test('parses a real labs row shape', () {
      final lab = AdminLab.fromRow({
        'id': 'lab1',
        'slug': 'sqli-101',
        'title': 'SQLi 101',
        'description': 'Find and exploit the injection.',
        'category': 'web',
        'difficulty': 'easy',
        'estimated_minutes': 45,
        'points': 100,
        'published': true,
      });
      expect(lab.id, 'lab1');
      expect(lab.estimatedMinutes, 45);
      expect(lab.published, true);
    });
  });

  group('AdminLabHint.fromRow', () {
    test('parses a real lab_hints row shape', () {
      final hint = AdminLabHint.fromRow({'id': 'h1', 'level': 2, 'content': 'Check the login form.', 'point_cost': 10});
      expect(hint.level, 2);
      expect(hint.pointCost, 10);
    });
  });

  group('AdminLabFlag.fromRow', () {
    test('parses a real lab_flags row shape', () {
      final flag = AdminLabFlag.fromRow({'id': 'f1', 'label': 'flag', 'variant_seed': 0});
      expect(flag.label, 'flag');
      expect(flag.variantSeed, 0);
    });
  });
}
