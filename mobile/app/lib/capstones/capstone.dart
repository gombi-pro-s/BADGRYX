class Capstone {
  Capstone({required this.id, required this.title, this.description, required this.reportRequired});

  final String id;
  final String title;
  final String? description;
  final bool reportRequired;

  factory Capstone.fromRow(Map<String, dynamic> row) {
    return Capstone(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      reportRequired: row['report_required'] as bool,
    );
  }
}

class CapstoneSubmission {
  CapstoneSubmission({
    required this.status,
    this.reviewerNotes,
    required this.submittedAt,
  });

  final String status; // 'submitted' | 'under_review' | 'passed' | 'needs_revision'
  final String? reviewerNotes;
  final DateTime submittedAt;

  factory CapstoneSubmission.fromRow(Map<String, dynamic> row) {
    return CapstoneSubmission(
      status: row['status'] as String,
      reviewerNotes: row['reviewer_notes'] as String?,
      submittedAt: DateTime.parse(row['submitted_at'] as String),
    );
  }
}

const Map<String, String> capstoneStatusLabel = {
  'submitted': 'Submitted',
  'under_review': 'Under review',
  'passed': 'Passed',
  'needs_revision': 'Needs revision',
};

/// Mirrors capstones/page.tsx exactly: submissions arrive newest-first, so
/// the FIRST submission seen per capstone is its latest status -- not the
/// highest-scoring or a re-sorted one.
Map<String, String> latestStatusByCapstone(List<Map<String, dynamic>> submissionRows) {
  final latest = <String, String>{};
  for (final row in submissionRows) {
    final capstoneId = row['capstone_id'] as String;
    if (!latest.containsKey(capstoneId)) {
      latest[capstoneId] = row['status'] as String;
    }
  }
  return latest;
}
