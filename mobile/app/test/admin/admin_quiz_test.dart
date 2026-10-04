import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/admin/admin_quiz.dart';

void main() {
  group('isValidQuizSlug', () {
    test('accepts lowercase letters, digits, hyphens, 3-64 chars', () {
      expect(isValidQuizSlug('sqli-quiz'), true);
    });

    test('rejects uppercase and too-short slugs', () {
      expect(isValidQuizSlug('SQLi-Quiz'), false);
      expect(isValidQuizSlug('ab'), false);
    });
  });

  group('AdminQuiz.fromRow', () {
    test('parses a real quizzes row shape', () {
      final quiz = AdminQuiz.fromRow({
        'id': 'q1',
        'slug': 'sqli-quiz',
        'title': 'SQLi Quiz',
        'is_exam': false,
        'published': true,
      });
      expect(quiz.id, 'q1');
      expect(quiz.isExam, false);
      expect(quiz.published, true);
    });
  });

  group('AdminQuizChoice.fromRow and AdminQuizQuestion.fromRow', () {
    test('parse real quiz_choices/quiz_questions row shapes', () {
      final choice = AdminQuizChoice.fromRow({'id': 'c1', 'choice_text': 'DROP TABLE', 'is_correct': true});
      expect(choice.text, 'DROP TABLE');
      expect(choice.isCorrect, true);

      final question = AdminQuizQuestion.fromRow({'id': 'qq1', 'question_text': 'Which is a SQLi payload?'}, [choice]);
      expect(question.questionText, 'Which is a SQLi payload?');
      expect(question.choices, [choice]);
    });
  });

  group('trimmedNonEmptyChoices', () {
    test('trims whitespace and drops choices that end up empty', () {
      final result = trimmedNonEmptyChoices([
        QuizChoiceDraft(text: '  A  ', isCorrect: true),
        QuizChoiceDraft(text: '   ', isCorrect: false),
        QuizChoiceDraft(text: 'B', isCorrect: false),
      ]);
      expect(result.map((c) => c.text).toList(), ['A', 'B']);
    });
  });

  group('quizChoicesError', () {
    test('requires at least two choices', () {
      expect(
        quizChoicesError([QuizChoiceDraft(text: 'A', isCorrect: true)]),
        'At least two choices are required.',
      );
    });

    test('requires at least one correct choice', () {
      expect(
        quizChoicesError([QuizChoiceDraft(text: 'A'), QuizChoiceDraft(text: 'B')]),
        'At least one choice must be marked correct.',
      );
    });

    test('null when there are two or more choices and at least one is correct', () {
      expect(quizChoicesError([QuizChoiceDraft(text: 'A', isCorrect: true), QuizChoiceDraft(text: 'B')]), null);
    });
  });
}
