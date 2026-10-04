class Report {
  Report({required this.id, required this.title, required this.kind, required this.contentMarkdown, required this.updatedAt});

  final String id;
  final String title;
  final String kind; // 'pentest_report' | 'methodology'
  final String contentMarkdown;
  final DateTime updatedAt;

  factory Report.fromRow(Map<String, dynamic> row) {
    return Report(
      id: row['id'] as String,
      title: row['title'] as String,
      kind: row['kind'] as String,
      contentMarkdown: row['content_markdown'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

/// Mirrors reports/page.tsx's KIND_LABELS lookup exactly, including its
/// `?? r.kind` fallback for a kind this map hasn't been updated for yet.
const Map<String, String> _reportKindLabels = {'pentest_report': 'Pentest report', 'methodology': 'Methodology write-up'};

String reportKindLabel(String kind) => _reportKindLabels[kind] ?? kind;
