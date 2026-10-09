import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/dashboard/announcement.dart';

void main() {
  group('Announcement.fromRow', () {
    test('parses a real announcements row shape', () {
      final announcement = Announcement.fromRow({
        'id': 'a1',
        'title': 'New CTF event live',
        'body_markdown': 'Details about the event...',
      });
      expect(announcement.id, 'a1');
      expect(announcement.title, 'New CTF event live');
      expect(announcement.bodyMarkdown, 'Details about the event...');
    });
  });

  group('planNameFromSubscriptionRow', () {
    test('returns Free when there is no active subscription row', () {
      expect(planNameFromSubscriptionRow(null), 'Free');
    });

    test('returns the joined plan name when a subscription exists', () {
      expect(
        planNameFromSubscriptionRow({
          'plan_id': 'p1',
          'status': 'active',
          'plans': {'name': 'Pro', 'slug': 'pro'},
        }),
        'Pro',
      );
    });

    test('falls back to Free if the subscription row has no joined plan', () {
      expect(planNameFromSubscriptionRow({'plan_id': 'p1', 'status': 'active', 'plans': null}), 'Free');
    });
  });

  group('pickAnnouncementText', () {
    final base = Announcement(id: 'a1', title: 'English title', bodyMarkdown: 'English body');
    final spanish = AnnouncementTranslation(
      announcementId: 'a1',
      locale: 'es',
      title: 'Título en español',
      bodyMarkdown: 'Cuerpo en español',
    );

    test('returns the base text when the locale is the default (en)', () {
      final text = pickAnnouncementText(base, [spanish], 'en');
      expect(text.title, 'English title');
      expect(text.bodyMarkdown, 'English body');
    });

    test('returns the matching translation when the locale has one', () {
      final text = pickAnnouncementText(base, [spanish], 'es');
      expect(text.title, 'Título en español');
      expect(text.bodyMarkdown, 'Cuerpo en español');
    });

    test('falls back to the base text when no translation matches the locale', () {
      final text = pickAnnouncementText(base, [], 'es');
      expect(text.title, 'English title');
      expect(text.bodyMarkdown, 'English body');
    });
  });
}
