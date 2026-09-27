class CtfChallenge {
  CtfChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.points,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String difficulty;
  final int points;

  factory CtfChallenge.fromRow(Map<String, dynamic> row) {
    return CtfChallenge(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      points: row['points'] as int,
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
