class Announcement {
  Announcement({required this.id, required this.title, required this.bodyMarkdown});

  final String id;
  final String title;
  final String bodyMarkdown;

  factory Announcement.fromRow(Map<String, dynamic> row) {
    return Announcement(
      id: row['id'] as String,
      title: row['title'] as String,
      bodyMarkdown: row['body_markdown'] as String,
    );
  }
}

/// Mirrors apps/web's dashboard/page.tsx: the plan name comes from the
/// user's active/trialing/past_due subscription's joined plan row, or
/// "Free" if none exists -- never invented client-side.
String planNameFromSubscriptionRow(Map<String, dynamic>? subscriptionRow) {
  if (subscriptionRow == null) return 'Free';
  final plan = subscriptionRow['plans'] as Map<String, dynamic>?;
  return (plan?['name'] as String?) ?? 'Free';
}
