class Investigation {
  Investigation({
    required this.id,
    required this.title,
    this.briefing,
    required this.category,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.points,
    required this.passingScore,
  });

  final String id;
  final String title;
  final String? briefing;
  final String category;
  final String difficulty;
  final int estimatedMinutes;
  final int points;
  final int passingScore;

  factory Investigation.fromRow(Map<String, dynamic> row) {
    return Investigation(
      id: row['id'] as String,
      title: row['title'] as String,
      briefing: row['briefing'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      estimatedMinutes: row['estimated_minutes'] as int,
      points: row['points'] as int,
      passingScore: row['passing_score'] as int,
    );
  }
}

class InvestigationArtifact {
  InvestigationArtifact({required this.id, required this.artifactType, required this.title, required this.content});

  final String id;
  final String artifactType;
  final String title;
  final String content;

  factory InvestigationArtifact.fromRow(Map<String, dynamic> row) {
    return InvestigationArtifact(
      id: row['id'] as String,
      artifactType: row['artifact_type'] as String,
      title: row['title'] as String,
      content: row['content'] as String,
    );
  }
}

class InvestigationChoice {
  InvestigationChoice({required this.choiceId, required this.choiceText});

  final String choiceId;
  final String choiceText;
}

class InvestigationQuestion {
  InvestigationQuestion({
    required this.questionId,
    required this.questionText,
    required this.questionType,
    required this.choices,
  });

  final String questionId;
  final String questionText;
  final String questionType; // 'multiple_choice' | 'exact_text'
  final List<InvestigationChoice> choices;
}

/// Groups the flat rows `investigation_questions_for_attempt` returns
/// (one row per question/choice pair) into one entry per question --
/// mirrors the Map-building loop in apps/web's investigate/[id]/page.tsx.
List<InvestigationQuestion> groupQuestionRows(List<Map<String, dynamic>> rows) {
  final byId = <String, InvestigationQuestion>{};
  final order = <String>[];
  for (final row in rows) {
    final questionId = row['question_id'] as String;
    if (!byId.containsKey(questionId)) {
      byId[questionId] = InvestigationQuestion(
        questionId: questionId,
        questionText: row['question_text'] as String,
        questionType: row['question_type'] as String,
        choices: [],
      );
      order.add(questionId);
    }
    final choiceId = row['choice_id'] as String?;
    final choiceText = row['choice_text'] as String?;
    if (choiceId != null && choiceText != null) {
      byId[questionId]!.choices.add(InvestigationChoice(choiceId: choiceId, choiceText: choiceText));
    }
  }
  return order.map((id) => byId[id]!).toList();
}

/// Mirrors investigation-answers.tsx's payload construction exactly: a
/// multiple_choice question submits its single selected choice id inside
/// a one-element list (or an empty list if unanswered); exact_text
/// submits the raw string (or an empty string if unanswered).
Map<String, Object> buildAnswersPayload(
  List<InvestigationQuestion> questions,
  Map<String, String> choiceAnswers,
  Map<String, String> textAnswers,
) {
  final payload = <String, Object>{};
  for (final q in questions) {
    if (q.questionType == 'multiple_choice') {
      final selected = choiceAnswers[q.questionId];
      payload[q.questionId] = selected != null ? [selected] : <String>[];
    } else {
      payload[q.questionId] = textAnswers[q.questionId] ?? '';
    }
  }
  return payload;
}

class BestSubmission {
  BestSubmission({required this.passed, required this.score});

  final bool passed;
  final int score;
}

/// Mirrors /investigate's list-page logic exactly: for each investigation,
/// the submission with the highest score wins (not the most recent one).
Map<String, BestSubmission> bestSubmissionByInvestigation(List<Map<String, dynamic>> submissionRows) {
  final best = <String, BestSubmission>{};
  for (final row in submissionRows) {
    final investigationId = row['investigation_id'] as String;
    final score = row['score'] as int;
    final passed = row['passed'] as bool;
    final current = best[investigationId];
    if (current == null || score > current.score) {
      best[investigationId] = BestSubmission(passed: passed, score: score);
    }
  }
  return best;
}
