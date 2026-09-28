import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/orgs/org_announcement.dart';

void main() {
  final now = DateTime.utc(2026, 1, 15, 12, 0, 0);

  OrgAnnouncement build({bool published = false, DateTime? expiresAt}) {
    return OrgAnnouncement(
      id: 'a1',
      title: 'Title',
      bodyMarkdown: 'Body',
      published: published,
      publishedAt: null,
      expiresAt: expiresAt,
      createdAt: now,
    );
  }

  group('isAnnouncementExpired', () {
    test('false when no expiry is set', () {
      expect(isAnnouncementExpired(build(), now), isFalse);
    });

    test('false when expiry is in the future', () {
      expect(isAnnouncementExpired(build(expiresAt: now.add(const Duration(days: 1))), now), isFalse);
    });

    test('true when expiry is in the past', () {
      expect(isAnnouncementExpired(build(expiresAt: now.subtract(const Duration(days: 1))), now), isTrue);
    });
  });

  group('announcementStatusLabel', () {
    test('Draft when unpublished and not expired', () {
      expect(announcementStatusLabel(build(published: false), now), 'Draft');
    });

    test('Published when published and not expired', () {
      expect(announcementStatusLabel(build(published: true), now), 'Published');
    });

    test('Expired wins over published when expiry has passed', () {
      final announcement = build(published: true, expiresAt: now.subtract(const Duration(hours: 1)));
      expect(announcementStatusLabel(announcement, now), 'Expired');
    });

    test('Expired even when unpublished', () {
      final announcement = build(published: false, expiresAt: now.subtract(const Duration(hours: 1)));
      expect(announcementStatusLabel(announcement, now), 'Expired');
    });
  });
}
