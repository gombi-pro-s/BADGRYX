import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/investigations/investigation.dart';

void main() {
  group('groupQuestionRows', () {
    test('groups multiple choice rows for the same question into one entry with all choices', () {
      final questions = groupQuestionRows([
        {
          'question_id': 'q1',
          'question_text': 'What technique?',
          'question_type': 'multiple_choice',
          'choice_id': 'c1',
          'choice_text': 'Phishing',
        },
        {
          'question_id': 'q1',
          'question_text': 'What technique?',
          'question_type': 'multiple_choice',
          'choice_id': 'c2',
          'choice_text': 'SQL injection',
        },
      ]);
      expect(questions.length, 1);
      expect(questions.first.choices.length, 2);
      expect(questions.first.choices.map((c) => c.choiceText), ['Phishing', 'SQL injection']);
    });

    test('an exact_text question with no choice columns gets an empty choices list', () {
      final questions = groupQuestionRows([
        {
          'question_id': 'q2',
          'question_text': 'What domain was used?',
          'question_type': 'exact_text',
          'choice_id': null,
          'choice_text': null,
        },
      ]);
      expect(questions.first.choices, isEmpty);
    });

    test('preserves question order across multiple questions', () {
      final questions = groupQuestionRows([
        {'question_id': 'q1', 'question_text': 'First', 'question_type': 'exact_text', 'choice_id': null, 'choice_text': null},
        {'question_id': 'q2', 'question_text': 'Second', 'question_type': 'exact_text', 'choice_id': null, 'choice_text': null},
      ]);
      expect(questions.map((q) => q.questionId), ['q1', 'q2']);
    });
  });

  group('buildAnswersPayload', () {
    final questions = [
      InvestigationQuestion(
        questionId: 'q1',
        questionText: 'MC question',
        questionType: 'multiple_choice',
        choices: [InvestigationChoice(choiceId: 'c1', choiceText: 'A'), InvestigationChoice(choiceId: 'c2', choiceText: 'B')],
      ),
      InvestigationQuestion(questionId: 'q2', questionText: 'Text question', questionType: 'exact_text', choices: []),
    ];

    test('wraps a selected multiple_choice answer in a one-element list', () {
      final payload = buildAnswersPayload(questions, {'q1': 'c2'}, {});
      expect(payload['q1'], ['c2']);
    });

    test('submits an empty list for an unanswered multiple_choice question', () {
      final payload = buildAnswersPayload(questions, {}, {});
      expect(payload['q1'], <String>[]);
    });

    test('submits the raw string for an exact_text answer', () {
      final payload = buildAnswersPayload(questions, {}, {'q2': 'invoice-billing-support.com'});
      expect(payload['q2'], 'invoice-billing-support.com');
    });

    test('submits an empty string for an unanswered exact_text question', () {
      final payload = buildAnswersPayload(questions, {}, {});
      expect(payload['q2'], '');
    });
  });

  group('bestSubmissionByInvestigation', () {
    test('picks the highest-scoring submission per investigation, not the most recent', () {
      final best = bestSubmissionByInvestigation([
        {'investigation_id': 'i1', 'passed': false, 'score': 40},
        {'investigation_id': 'i1', 'passed': true, 'score': 90},
        {'investigation_id': 'i1', 'passed': false, 'score': 60},
      ]);
      expect(best['i1']!.score, 90);
      expect(best['i1']!.passed, isTrue);
    });

    test('tracks separate bests for separate investigations', () {
      final best = bestSubmissionByInvestigation([
        {'investigation_id': 'i1', 'passed': true, 'score': 80},
        {'investigation_id': 'i2', 'passed': false, 'score': 30},
      ]);
      expect(best['i1']!.score, 80);
      expect(best['i2']!.score, 30);
    });

    test('an investigation with no submissions has no entry', () {
      final best = bestSubmissionByInvestigation([]);
      expect(best['i1'], isNull);
    });
  });
}
