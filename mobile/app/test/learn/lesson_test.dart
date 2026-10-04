import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/learn/lesson.dart';

void main() {
  group('groupLessonsByModule', () {
    test('buckets lessons under their module id, preserving input order', () {
      final byModule = groupLessonsByModule([
        LessonSummary(id: 'l1', moduleId: 'm1', title: 'First', estimatedMinutes: 5),
        LessonSummary(id: 'l2', moduleId: 'm2', title: 'Other module', estimatedMinutes: 10),
        LessonSummary(id: 'l3', moduleId: 'm1', title: 'Second', estimatedMinutes: 8),
      ]);
      expect(byModule.keys, ['m1', 'm2']);
      expect(byModule['m1']!.map((l) => l.id), ['l1', 'l3']);
      expect(byModule['m2']!.map((l) => l.id), ['l2']);
    });

    test('an empty lesson list produces an empty map', () {
      expect(groupLessonsByModule([]), isEmpty);
    });
  });

  group('groupLessonQuizRows', () {
    test('groups choices under their question and keeps quiz-level fields from the first row', () {
      final quiz = groupLessonQuizRows([
        {
          'quiz_id': 'quiz1',
          'title': 'Comprehension check',
          'passing_score': 70,
          'question_id': 'q1',
          'question_text': 'What is X?',
          'question_type': 'single_choice',
          'choice_id': 'c1',
          'choice_text': 'A',
        },
        {
          'quiz_id': 'quiz1',
          'title': 'Comprehension check',
          'passing_score': 70,
          'question_id': 'q1',
          'question_text': 'What is X?',
          'question_type': 'single_choice',
          'choice_id': 'c2',
          'choice_text': 'B',
        },
      ]);
      expect(quiz.quizId, 'quiz1');
      expect(quiz.title, 'Comprehension check');
      expect(quiz.passingScore, 70);
      expect(quiz.questions.length, 1);
      expect(quiz.questions.first.choices.map((c) => c.choiceText), ['A', 'B']);
    });

    test('a question row with no choice columns still parses with an empty choices list', () {
      final quiz = groupLessonQuizRows([
        {
          'quiz_id': 'quiz1',
          'title': 'Q',
          'passing_score': 50,
          'question_id': 'q1',
          'question_text': 'Explain X',
          'question_type': 'short_answer',
          'choice_id': null,
          'choice_text': null,
        },
      ]);
      expect(quiz.questions.first.choices, isEmpty);
    });
  });

  group('buildLessonQuizAnswerPayload', () {
    test('wraps a selected answer in a single-element list', () {
      final questions = [
        LessonQuizQuestion(questionId: 'q1', questionText: 'Q', questionType: 'single_choice', choices: []),
      ];
      final payload = buildLessonQuizAnswerPayload(questions, {'q1': 'c1'});
      expect(payload, {'q1': ['c1']});
    });

    test('an unanswered question gets an empty list, even for a multi_choice question', () {
      final questions = [
        LessonQuizQuestion(questionId: 'q1', questionText: 'Q', questionType: 'multi_choice', choices: []),
      ];
      final payload = buildLessonQuizAnswerPayload(questions, {});
      expect(payload, {'q1': []});
    });
  });
}
