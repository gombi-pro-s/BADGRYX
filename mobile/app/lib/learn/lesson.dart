import '../i18n/locale.dart';

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

/// Mirrors `types/database.ts`'s own `LearningPathTranslationRow` (the
/// subset `pickPathText()` actually reads).
class LearningPathTranslation {
  LearningPathTranslation({required this.pathId, required this.locale, required this.title, required this.description});

  final String pathId;
  final String locale;
  final String title;
  final String? description;

  factory LearningPathTranslation.fromRow(Map<String, dynamic> row) {
    return LearningPathTranslation(
      pathId: row['path_id'] as String,
      locale: row['locale'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
    );
  }
}

typedef PathText = ({String title, String? description});

/// Direct port of `pickPathText()` (`lib/i18n/content-translation.ts`,
/// ADR 0064): the base `LearningPathSummary` row IS the default-locale
/// ('en') text; a translation row only exists for a non-default locale
/// that has one. Falls back to the base text whenever `locale` is the
/// default, or no translation row matches it. See ADR 0065 for this
/// function's first mobile reader.
PathText pickPathText(LearningPathSummary base, List<LearningPathTranslation> translations, String locale) {
  if (locale == defaultLocale) return (title: base.title, description: base.description);
  for (final t in translations) {
    if (t.locale == locale) return (title: t.title, description: t.description);
  }
  return (title: base.title, description: base.description);
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

/// Mirrors `types/database.ts`'s own `LessonTranslationRow` (the subset
/// `pickLessonText()` actually reads).
class LessonTranslation {
  LessonTranslation({required this.lessonId, required this.locale, required this.title, required this.contentMarkdown});

  final String lessonId;
  final String locale;
  final String title;
  final String contentMarkdown;

  factory LessonTranslation.fromRow(Map<String, dynamic> row) {
    return LessonTranslation(
      lessonId: row['lesson_id'] as String,
      locale: row['locale'] as String,
      title: row['title'] as String,
      contentMarkdown: row['content_markdown'] as String,
    );
  }
}

typedef LessonText = ({String title, String contentMarkdown});

/// Direct port of `pickLessonText()` (`lib/i18n/content-translation.ts`,
/// ADR 0064). `base` only needs `title`/`contentMarkdown` -- a lesson
/// summary row that has no `content_markdown` of its own (this app's
/// `LessonSummary`, used for a title-only list row) passes `''` for it,
/// the same way `learn/[pathId]/page.tsx` does on web.
LessonText pickLessonText(({String title, String contentMarkdown}) base, List<LessonTranslation> translations, String locale) {
  if (locale == defaultLocale) return base;
  for (final t in translations) {
    if (t.locale == locale) return (title: t.title, contentMarkdown: t.contentMarkdown);
  }
  return base;
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
