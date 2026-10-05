import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/ctf/ctf_event.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1, 12, 0, 0);

  group('ctfEventStatus', () {
    test('is upcoming when now is before starts_at', () {
      expect(ctfEventStatus(DateTime.utc(2026, 6, 1, 13, 0, 0), null, now: now), CtfEventStatus.upcoming);
    });

    test('is ended when now is at or after ends_at', () {
      expect(ctfEventStatus(null, DateTime.utc(2026, 6, 1, 12, 0, 0), now: now), CtfEventStatus.ended);
      expect(ctfEventStatus(null, DateTime.utc(2026, 6, 1, 11, 0, 0), now: now), CtfEventStatus.ended);
    });

    test('is live when now is between starts_at and ends_at', () {
      expect(
        ctfEventStatus(DateTime.utc(2026, 6, 1, 11, 0, 0), DateTime.utc(2026, 6, 1, 13, 0, 0), now: now),
        CtfEventStatus.live,
      );
    });

    test('is live with no bounds at all', () {
      expect(ctfEventStatus(null, null, now: now), CtfEventStatus.live);
    });

    test('is live with only a past start and no end', () {
      expect(ctfEventStatus(DateTime.utc(2026, 6, 1, 11, 0, 0), null, now: now), CtfEventStatus.live);
    });

    test("is upcoming even with an end date, if the start hasn't arrived yet", () {
      expect(
        ctfEventStatus(DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3), now: now),
        CtfEventStatus.upcoming,
      );
    });
  });

  group('formatCtfEventDuration', () {
    test('shows minutes and seconds for a same-day duration', () {
      expect(formatCtfEventDuration(const Duration(minutes: 5, seconds: 9)), '5m 9s');
    });

    test('shows days, hours, and minutes, but never seconds, once a day has passed', () {
      expect(formatCtfEventDuration(const Duration(days: 2, hours: 3, minutes: 10, seconds: 59)), '2d 3h 10m');
    });

    test('shows days and hours only, no minutes, when the hour component is exactly zero', () {
      expect(formatCtfEventDuration(const Duration(days: 1, minutes: 45)), '1d 0h');
    });

    test('shows hours, minutes, and seconds for an under-a-day duration with hours', () {
      expect(formatCtfEventDuration(const Duration(hours: 1, minutes: 30, seconds: 45)), '1h 30m 45s');
    });

    test('a negative (already-elapsed) duration clamps to zero', () {
      expect(formatCtfEventDuration(const Duration(seconds: -5)), '0m 0s');
    });
  });
}
