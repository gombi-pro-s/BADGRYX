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
}
