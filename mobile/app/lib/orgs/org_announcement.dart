class OrgAnnouncement {
  OrgAnnouncement({
    required this.id,
    required this.title,
    required this.bodyMarkdown,
    required this.published,
    required this.publishedAt,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String bodyMarkdown;
  final bool published;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory OrgAnnouncement.fromRow(Map<String, dynamic> row) {
    return OrgAnnouncement(
      id: row['id'] as String,
      title: row['title'] as String,
      bodyMarkdown: row['body_markdown'] as String? ?? '',
      published: row['published'] as bool,
      publishedAt: row['published_at'] != null ? DateTime.parse(row['published_at'] as String) : null,
      expiresAt: row['expires_at'] != null ? DateTime.parse(row['expires_at'] as String) : null,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

/// Mirrors orgs/[orgId]/announcements/page.tsx's inline `expired` check.
bool isAnnouncementExpired(OrgAnnouncement announcement, DateTime now) {
  final expiresAt = announcement.expiresAt;
  return expiresAt != null && expiresAt.isBefore(now);
}

/// Mirrors that same page's expired/published/draft badge ternary exactly:
/// expired wins over published.
String announcementStatusLabel(OrgAnnouncement announcement, DateTime now) {
  if (isAnnouncementExpired(announcement, now)) return 'Expired';
  return announcement.published ? 'Published' : 'Draft';
}

/// Mirrors admin/announcements/actions.ts's upsertSpanishTranslation()
/// branch condition exactly: only upsert when BOTH fields are filled;
/// either blank means "no translation" and the row should be deleted.
bool shouldUpsertSpanishTranslation(String titleEs, String bodyEs) => titleEs.isNotEmpty && bodyEs.isNotEmpty;
