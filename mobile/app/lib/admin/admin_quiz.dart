/// Mirrors `types/database.ts`'s `HintPolicy` union -- the fixed value
/// set `admin/quizzes/create-quiz-form.tsx` renders as `<select>` options.
const List<String> quizHintPolicies = ['none', 'limited', 'full'];

final RegExp _slugPattern = RegExp(r'^[a-z0-9-]{3,64}$');

/// Mirrors `admin/quizzes/actions.ts`'s zod slug schema: lowercase
/// letters, digits, hyphens, 3-64 chars -- the exact same rule every other
/// admin CMS slug field in this app enforces.
bool isValidQuizSlug(String slug) => _slugPattern.hasMatch(slug);

class AdminQuiz {
  AdminQuiz({
    required this.id,
    required this.slug,
    required this.title,
    required this.isExam,
    required this.published,
  });

  final String id;
  final String slug;
  final String title;
  final bool isExam;
  final bool published;

  factory AdminQuiz.fromRow(Map<String, dynamic> row) {
    return AdminQuiz(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      isExam: row['is_exam'] as bool,
      published: row['published'] as bool,
    );
  }
}

class AdminQuizChoice {
  AdminQuizChoice({required this.id, required this.text, required this.isCorrect});

  final String id;
  final String text;
  final bool isCorrect;

  factory AdminQuizChoice.fromRow(Map<String, dynamic> row) {
    return AdminQuizChoice(
      id: row['id'] as String,
      text: row['choice_text'] as String,
      isCorrect: row['is_correct'] as bool,
    );
  }
}

class AdminQuizQuestion {
  AdminQuizQuestion({required this.id, required this.questionText, required this.choices});

  final String id;
  final String questionText;
  final List<AdminQuizChoice> choices;

  factory AdminQuizQuestion.fromRow(Map<String, dynamic> row, List<AdminQuizChoice> choices) {
    return AdminQuizQuestion(id: row['id'] as String, questionText: row['question_text'] as String, choices: choices);
  }
}

/// A single choice being drafted in the "Add question" form -- mirrors
/// `questions-manager.tsx`'s own `ChoiceInput` shape.
class QuizChoiceDraft {
  QuizChoiceDraft({this.text = '', this.isCorrect = false});

  String text;
  bool isCorrect;
}

/// Mirrors `createQuestionAction()`'s own trim-then-filter step exactly:
/// trims each choice's text and drops any that end up empty.
List<QuizChoiceDraft> trimmedNonEmptyChoices(List<QuizChoiceDraft> choices) {
  return choices
      .map((c) => QuizChoiceDraft(text: c.text.trim(), isCorrect: c.isCorrect))
      .where((c) => c.text.isNotEmpty)
      .toList();
}

/// Mirrors `createQuestionAction()`'s own two validation checks, run on an
/// already-trimmed-and-filtered choice list (see [trimmedNonEmptyChoices]).
/// Returns the exact same error message, or null when the list is valid.
String? quizChoicesError(List<QuizChoiceDraft> trimmedChoices) {
  if (trimmedChoices.length < 2) return 'At least two choices are required.';
  if (!trimmedChoices.any((c) => c.isCorrect)) return 'At least one choice must be marked correct.';
  return null;
}
