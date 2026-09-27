import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/exams/exam.dart';

void main() {
  group('groupExamQuestionRows', () {
    test('groups choices for the same question and sorts by order_index', () {
      final questions = groupExamQuestionRows([
        {
          'question_id': 'q2',
          'question_text': 'Second',
          'question_type': 'single_choice',
          'points': 1,
          'order_index': 1,
          'choice_id': 'c3',
          'choice_text': 'X',
        },
        {
          'question_id': 'q1',
          'question_text': 'First',
          'question_type': 'multi_choice',
          'points': 2,
          'order_index': 0,
          'choice_id': 'c1',
          'choice_text': 'A',
        },
        {
          'question_id': 'q1',
          'question_text': 'First',
          'question_type': 'multi_choice',
          'points': 2,
          'order_index': 0,
          'choice_id': 'c2',
          'choice_text': 'B',
        },
      ]);
      expect(questions.map((q) => q.questionId), ['q1', 'q2']);
      expect(questions.first.choices.length, 2);
    });

    test('a short_answer question with no choice columns still parses with an empty choices list', () {
      final questions = groupExamQuestionRows([
        {
          'question_id': 'q1',
          'question_text': 'Explain X',
          'question_type': 'short_answer',
          'points': 1,
          'order_index': 0,
          'choice_id': null,
          'choice_text': null,
        },
      ]);
      expect(questions.first.choices, isEmpty);
    });
  });

  group('toggleChoice', () {
    test('a single-select question always replaces the selection with the new choice', () {
      expect(toggleChoice(['c1'], 'c2', multi: false), ['c2']);
      expect(toggleChoice([], 'c1', multi: false), ['c1']);
    });

    test('a multi-select question adds an unselected choice', () {
      expect(toggleChoice(['c1'], 'c2', multi: true), ['c1', 'c2']);
    });

    test('a multi-select question removes an already-selected choice', () {
      expect(toggleChoice(['c1', 'c2'], 'c1', multi: true), ['c2']);
    });
  });

  group('formatExamTime', () {
    test('formats whole minutes with zero-padded seconds', () {
      expect(formatExamTime(125), '2:05');
    });

    test('formats under a minute', () {
      expect(formatExamTime(45), '0:45');
    });

    test('formats exactly zero', () {
      expect(formatExamTime(0), '0:00');
    });
  });

  group('attemptsRemaining', () {
    test('returns null when there is no attempt limit', () {
      expect(attemptsRemaining(null, 5), isNull);
    });

    test('returns the real remaining count', () {
      expect(attemptsRemaining(3, 1), 2);
    });

    test('never goes negative when attempts used exceeds the limit', () {
      expect(attemptsRemaining(2, 5), 0);
    });
  });
}
