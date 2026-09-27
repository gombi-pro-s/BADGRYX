import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/labs/lab.dart';

void main() {
  group('Lab.fromRow', () {
    test('parses a real labs row shape', () {
      final lab = Lab.fromRow({
        'id': 'l1',
        'title': 'Linux Privilege Escalation: Misconfigured Sudo',
        'description': 'Escalate via an unrestricted sudo rule.',
        'category': 'linux',
        'difficulty': 'medium',
        'points': 150,
        'has_terminal': true,
      });
      expect(lab.id, 'l1');
      expect(lab.title, 'Linux Privilege Escalation: Misconfigured Sudo');
      expect(lab.category, 'linux');
      expect(lab.difficulty, 'medium');
      expect(lab.points, 150);
      expect(lab.hasTerminal, isTrue);
    });

    test('a lab with no terminal environment parses hasTerminal as false', () {
      final lab = Lab.fromRow({
        'id': 'l2',
        'title': 'No terminal lab',
        'description': null,
        'category': 'web',
        'difficulty': 'easy',
        'points': 100,
        'has_terminal': false,
      });
      expect(lab.hasTerminal, isFalse);
      expect(lab.description, isNull);
    });
  });

  test('LabHint.fromRow parses a real lab_hints row shape', () {
    final hint = LabHint.fromRow({'id': 'h1', 'level': 2, 'point_cost': 10});
    expect(hint.id, 'h1');
    expect(hint.level, 2);
    expect(hint.pointCost, 10);
  });

  group('LabInstance.fromRow', () {
    test('parses a real lab_instances row shape', () {
      final instance = LabInstance.fromRow({'id': 'i1', 'guided': true, 'status': 'running'});
      expect(instance.id, 'i1');
      expect(instance.guided, isTrue);
      expect(instance.status, 'running');
    });

    test('parses an unguided instance', () {
      final instance = LabInstance.fromRow({'id': 'i2', 'guided': false, 'status': 'running'});
      expect(instance.guided, isFalse);
    });
  });

  group('submissionCorrect', () {
    test('true for a correct submission row', () {
      expect(submissionCorrect({'correct': true, 'id': 's1'}), isTrue);
    });

    test('false for an incorrect submission row', () {
      expect(submissionCorrect({'correct': false, 'id': 's2'}), isFalse);
    });
  });
}
