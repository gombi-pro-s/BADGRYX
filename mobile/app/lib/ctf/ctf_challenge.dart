class CtfChallenge {
  CtfChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.points,
    required this.currentPoints,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String difficulty;
  final int points;

  /// What solving this challenge RIGHT NOW would award -- equals [points]
  /// for a static-scoring event or an independent challenge, decays
  /// toward the challenge's own floor for a dynamic-scoring event. Always
  /// display this, never [points], so this screen can never show a value
  /// `submit_ctf_flag()` wouldn't actually award. See ADR 0062 (mobile)
  /// and 20260922000031_ctf_dynamic_scoring.sql (web/SQL).
  final int currentPoints;

  factory CtfChallenge.fromRow(Map<String, dynamic> row) {
    return CtfChallenge(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      points: row['points'] as int,
      currentPoints: row['current_points'] as int,
    );
  }
}

/// The result of a real submit_ctf_flag() RPC call -- the *only* way this
/// app ever learns whether a flag was correct, exactly like apps/web
/// (never client-side flag comparison).
class CtfSubmissionResult {
  CtfSubmissionResult({required this.correct, required this.pointsAwarded});

  final bool correct;
  final int pointsAwarded;

  factory CtfSubmissionResult.fromRow(Map<String, dynamic> row) {
    return CtfSubmissionResult(correct: row['correct'] as bool, pointsAwarded: row['points_awarded'] as int);
  }
}
