class Exam {
  Exam({
    required this.id,
    required this.title,
    required this.passingScore,
    this.maxAttempts,
    this.timeLimitMinutes,
  });

  final String id;
  final String title;
  final num passingScore;
  final int? maxAttempts;
  final int? timeLimitMinutes;

  factory Exam.fromRow(Map<String, dynamic> row) {
    return Exam(
      id: row['id'] as String,
      title: row['title'] as String,
      passingScore: row['passing_score'] as num,
      maxAttempts: row['max_attempts'] as int?,
      timeLimitMinutes: row['time_limit_minutes'] as int?,
    );
  }
}

class ExamChoice {
  ExamChoice({required this.choiceId, required this.choiceText});

  final String choiceId;
  final String choiceText;
}

class ExamQuestion {
  ExamQuestion({
    required this.questionId,
    required this.questionText,
    required this.questionType,
    required this.points,
    required this.orderIndex,
    required this.choices,
  });

  final String questionId;
  final String questionText;
  final String questionType; // 'single_choice' | 'multi_choice' | 'true_false' | 'short_answer'
  final num points;
  final int orderIndex;
  final List<ExamChoice> choices;
}

/// Mirrors exams/[quizId]/page.tsx's inline grouping of
/// quiz_questions_for_attempt's flat rows, then its own
/// `.sort((a, b) => a.order_index - b.order_index)`.
List<ExamQuestion> groupExamQuestionRows(List<Map<String, dynamic>> rows) {
  final byId = <String, ExamQuestion>{};
  for (final row in rows) {
    final questionId = row['question_id'] as String;
    var question = byId[questionId];
    if (question == null) {
      question = ExamQuestion(
        questionId: questionId,
        questionText: row['question_text'] as String,
        questionType: row['question_type'] as String,
        points: row['points'] as num,
        orderIndex: row['order_index'] as int,
        choices: [],
      );
      byId[questionId] = question;
    }
    final choiceId = row['choice_id'] as String?;
    final choiceText = row['choice_text'] as String?;
    if (choiceId != null && choiceText != null) {
      question.choices.add(ExamChoice(choiceId: choiceId, choiceText: choiceText));
    }
  }
  final questions = byId.values.toList();
  questions.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  return questions;
}

/// Mirrors exam-attempt.tsx's toggleSingle/toggleMulti exactly: a single-
/// select question always replaces its selection with a one-element list;
/// a multi-select question toggles membership.
List<String> toggleChoice(List<String> current, String choiceId, {required bool multi}) {
  if (!multi) return [choiceId];
  return current.contains(choiceId) ? current.where((c) => c != choiceId).toList() : [...current, choiceId];
}

/// Mirrors exam-attempt.tsx's formatTime(totalSeconds) exactly.
String formatExamTime(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Mirrors exams/page.tsx's `attemptsRemaining` calc used for the used/
/// allowed display, and the detail page's attempt-exhaustion guard.
int? attemptsRemaining(int? maxAttempts, int attemptsUsed) {
  if (maxAttempts == null) return null;
  final remaining = maxAttempts - attemptsUsed;
  return remaining < 0 ? 0 : remaining;
}
