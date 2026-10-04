class LearningPathSummary {
  LearningPathSummary({required this.id, required this.title, required this.description});

  final String id;
  final String title;
  final String? description;

  factory LearningPathSummary.fromRow(Map<String, dynamic> row) {
    return LearningPathSummary(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
    );
  }
}

/// Mirrors `learn/[pathId]/page.tsx`'s own lesson-list row shape --
/// `moduleId` groups lessons under their module the same way that page's
/// `lessonsByModule` Map does.
class LessonSummary {
  LessonSummary({
    required this.id,
    required this.moduleId,
    required this.title,
    required this.estimatedMinutes,
  });

  final String id;
  final String moduleId;
  final String title;
  final int estimatedMinutes;

  factory LessonSummary.fromRow(Map<String, dynamic> row) {
    return LessonSummary(
      id: row['id'] as String,
      moduleId: row['module_id'] as String,
      title: row['title'] as String,
      estimatedMinutes: row['estimated_minutes'] as int,
    );
  }
}

/// Mirrors `learn/[pathId]/page.tsx`'s own grouping of its flat lesson
/// rows by `module_id` (order already comes from the query's own
/// `order_index` ordering, so this just buckets, never re-sorts).
Map<String, List<LessonSummary>> groupLessonsByModule(List<LessonSummary> lessons) {
  final byModule = <String, List<LessonSummary>>{};
  for (final lesson in lessons) {
    (byModule[lesson.moduleId] ??= []).add(lesson);
  }
  return byModule;
}

class LessonDetail {
  LessonDetail({required this.id, required this.title, required this.contentMarkdown});

  final String id;
  final String title;
  final String contentMarkdown;

  factory LessonDetail.fromRow(Map<String, dynamic> row) {
    return LessonDetail(
      id: row['id'] as String,
      title: row['title'] as String,
      contentMarkdown: row['content_markdown'] as String,
    );
  }
}

class LessonQuizChoice {
  LessonQuizChoice({required this.choiceId, required this.choiceText});

  final String choiceId;
  final String choiceText;
}

class LessonQuizQuestion {
  LessonQuizQuestion({
    required this.questionId,
    required this.questionText,
    required this.questionType,
    required this.choices,
  });

  final String questionId;
  final String questionText;
  final String questionType;
  final List<LessonQuizChoice> choices;
}

class LessonQuiz {
  LessonQuiz({required this.quizId, required this.title, required this.passingScore, required this.questions});

  final String quizId;
  final String title;
  final num passingScore;
  final List<LessonQuizQuestion> questions;
}

/// Mirrors `[lessonId]/page.tsx`'s own inline grouping of
/// `quiz_questions_for_attempt`'s flat rows into one entry per question
/// with its choices -- note this page never re-sorts by `order_index`
/// (unlike the dedicated Exams flow's own grouping), so this doesn't
/// either; a lesson's embedded comprehension-check quiz can render its
/// questions in whatever order the rows come back in, same as web.
LessonQuiz groupLessonQuizRows(List<Map<String, dynamic>> rows) {
  final byId = <String, LessonQuizQuestion>{};
  for (final row in rows) {
    final questionId = row['question_id'] as String;
    var question = byId[questionId];
    if (question == null) {
      question = LessonQuizQuestion(
        questionId: questionId,
        questionText: row['question_text'] as String,
        questionType: row['question_type'] as String,
        choices: [],
      );
      byId[questionId] = question;
    }
    final choiceId = row['choice_id'] as String?;
    final choiceText = row['choice_text'] as String?;
    if (choiceId != null && choiceText != null) {
      question.choices.add(LessonQuizChoice(choiceId: choiceId, choiceText: choiceText));
    }
  }
  return LessonQuiz(
    quizId: rows.first['quiz_id'] as String,
    title: rows.first['title'] as String,
    passingScore: rows.first['passing_score'] as num,
    questions: byId.values.toList(),
  );
}

/// Mirrors `quiz-attempt.tsx`'s own payload construction exactly: every
/// question gets a single-element (or empty) list, regardless of its
/// `question_type` -- this embedded lesson quiz, unlike the dedicated
/// Exams flow's `exam-attempt.tsx`, only ever lets you pick one choice
/// per question even for a `multi_choice` question. Not a mobile gap;
/// the web lesson page has the exact same limitation.
Map<String, List<String>> buildLessonQuizAnswerPayload(
  List<LessonQuizQuestion> questions,
  Map<String, String> answers,
) {
  return {for (final q in questions) q.questionId: answers.containsKey(q.questionId) ? [answers[q.questionId]!] : []};
}
