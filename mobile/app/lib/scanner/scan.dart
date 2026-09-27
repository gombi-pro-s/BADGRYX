class Scan {
  Scan({
    required this.id,
    required this.title,
    required this.status,
    required this.totalFiles,
    required this.totalFindings,
    required this.findingsBySeverity,
    required this.createdAt,
    this.errorMessage,
  });

  final String id;
  final String title;
  final String status; // 'pending' | 'running' | 'completed' | 'failed'
  final int totalFiles;
  final int totalFindings;
  final Map<String, int> findingsBySeverity;
  final DateTime createdAt;
  final String? errorMessage;

  factory Scan.fromRow(Map<String, dynamic> row) {
    final rawSeverity = row['findings_by_severity'] as Map<String, dynamic>? ?? const {};
    return Scan(
      id: row['id'] as String,
      title: row['title'] as String,
      status: row['status'] as String,
      totalFiles: row['total_files'] as int,
      totalFindings: row['total_findings'] as int,
      findingsBySeverity: rawSeverity.map((key, value) => MapEntry(key, value as int)),
      createdAt: DateTime.parse(row['created_at'] as String),
      errorMessage: row['error_message'] as String?,
    );
  }
}

class ScanFinding {
  ScanFinding({
    required this.id,
    required this.fileId,
    required this.ruleId,
    required this.category,
    required this.title,
    required this.severity,
    required this.confidence,
    required this.lineStart,
    required this.lineEnd,
    required this.evidence,
    required this.explanation,
    required this.impact,
    required this.remediation,
    required this.secureExample,
    required this.verificationStatus,
    required this.aiEnriched,
    required this.status,
  });

  final String id;
  final String fileId;
  final String ruleId;
  final String category;
  final String title;
  final String severity; // 'critical' | 'high' | 'medium' | 'low' | 'info'
  final String confidence; // 'high' | 'medium' | 'low'
  final int lineStart;
  final int lineEnd;
  final String evidence;
  final String explanation;
  final String impact;
  final String remediation;
  final String? secureExample;
  final String verificationStatus;
  final bool aiEnriched;
  final String status;

  factory ScanFinding.fromRow(Map<String, dynamic> row) {
    return ScanFinding(
      id: row['id'] as String,
      fileId: row['file_id'] as String,
      ruleId: row['rule_id'] as String,
      category: row['category'] as String,
      title: row['title'] as String,
      severity: row['severity'] as String,
      confidence: row['confidence'] as String,
      lineStart: row['line_start'] as int,
      lineEnd: row['line_end'] as int,
      evidence: row['evidence'] as String,
      explanation: row['explanation'] as String,
      impact: row['impact'] as String,
      remediation: row['remediation'] as String,
      secureExample: row['secure_example'] as String?,
      verificationStatus: row['verification_status'] as String,
      aiEnriched: row['ai_enriched'] as bool,
      status: row['status'] as String,
    );
  }
}

/// Mirrors apps/web's components/severity-badge.tsx SEVERITY_META labels
/// exactly.
const Map<String, String> severityLabel = {
  'critical': 'Critical',
  'high': 'High',
  'medium': 'Medium',
  'low': 'Low',
  'info': 'Info',
};

/// Postgres orders the scan_finding_severity enum by its declared value
/// order ('critical','high','medium','low','info') -- this is that same
/// order, used to render posture/findings most-severe-first without a
/// second round-trip to re-sort by severity.
const List<String> severityOrder = ['critical', 'high', 'medium', 'low', 'info'];

/// Mirrors scanner/page.tsx's inline posture aggregation: sums each scan's
/// findings_by_severity across every scan into one combined tally.
Map<String, int> aggregatePosture(List<Scan> scans) {
  final posture = <String, int>{};
  for (final scan in scans) {
    for (final entry in scan.findingsBySeverity.entries) {
      posture[entry.key] = (posture[entry.key] ?? 0) + entry.value;
    }
  }
  return posture;
}

/// Drops the fractional seconds off DateTime's default toString() --
/// "2026-01-01 12:00:00.000" -> "2026-01-01 12:00:00".
String formatScanTimestamp(DateTime dateTime) => dateTime.toLocal().toString().split('.').first;
