import '../i18n/locale.dart';

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

/// Mirrors `types/database.ts`'s own `AnnouncementTranslationRow` (the
/// subset `pickAnnouncementText()` actually reads).
class AnnouncementTranslation {
  AnnouncementTranslation({required this.announcementId, required this.locale, required this.title, required this.bodyMarkdown});

  final String announcementId;
  final String locale;
  final String title;
  final String bodyMarkdown;

  factory AnnouncementTranslation.fromRow(Map<String, dynamic> row) {
    return AnnouncementTranslation(
      announcementId: row['announcement_id'] as String,
      locale: row['locale'] as String,
      title: row['title'] as String,
      bodyMarkdown: row['body_markdown'] as String,
    );
  }
}

/// A plain (title, bodyMarkdown) pair -- this app's own equivalent of
/// `lib/i18n/announcement-translation.ts`'s `AnnouncementText` interface.
typedef AnnouncementText = ({String title, String bodyMarkdown});

/// Direct port of `pickAnnouncementText()`: the base `Announcement` row
/// IS the default-locale ('en') text; a translation row only exists for
/// a non-default locale that has one. Falls back to the base text
/// whenever `locale` is the default, or no translation row matches it.
/// See ADR 0038 (the original announcement_translations feature) and
/// ADR 0065 (this function's first mobile reader).
AnnouncementText pickAnnouncementText(Announcement base, List<AnnouncementTranslation> translations, String locale) {
  if (locale == defaultLocale) return (title: base.title, bodyMarkdown: base.bodyMarkdown);
  for (final t in translations) {
    if (t.locale == locale) return (title: t.title, bodyMarkdown: t.bodyMarkdown);
  }
  return (title: base.title, bodyMarkdown: base.bodyMarkdown);
}
