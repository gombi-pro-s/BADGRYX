/// Mirrors `lib/ctf/event-status.ts`'s own `CtfEventStatus` union and
/// `ctfEventStatus()` exactly -- pure classification, shared by the
/// static list badge and the ticking countdown banner, same split as web.
enum CtfEventStatus { upcoming, live, ended }

CtfEventStatus ctfEventStatus(DateTime? startsAt, DateTime? endsAt, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  if (startsAt != null && effectiveNow.isBefore(startsAt)) return CtfEventStatus.upcoming;
  if (endsAt != null && !effectiveNow.isBefore(endsAt)) return CtfEventStatus.ended;
  return CtfEventStatus.live;
}

String ctfEventStatusLabel(CtfEventStatus status) {
  switch (status) {
    case CtfEventStatus.upcoming:
      return 'Upcoming';
    case CtfEventStatus.live:
      return 'Live';
    case CtfEventStatus.ended:
      return 'Ended';
  }
}

/// Mirrors `event-status-banner.tsx`'s own `formatDuration()` exactly,
/// including its one real quirk: once at least a day has passed, seconds
/// never show again (only the `days === 0` branch pushes minutes AND
/// seconds together), and if a multi-day duration's hour component is
/// exactly zero, minutes don't show either -- e.g. "1d 0h" rather than
/// "1d 0h 45m". Not "fixed" here -- same display either client shows.
String formatCtfEventDuration(Duration duration) {
  final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final parts = <String>[];
  if (days > 0) parts.add('${days}d');
  if (days > 0 || hours > 0) parts.add('${hours}h');
  if (days == 0) {
    parts.add('${minutes}m');
    parts.add('${seconds}s');
  } else if (hours > 0) {
    parts.add('${minutes}m');
  }
  return parts.join(' ');
}

class CtfEventSummary {
  CtfEventSummary({required this.id, required this.slug, required this.title, required this.startsAt, required this.endsAt});

  final String id;
  final String slug;
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory CtfEventSummary.fromRow(Map<String, dynamic> row) {
    return CtfEventSummary(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      startsAt: row['starts_at'] != null ? DateTime.parse(row['starts_at'] as String) : null,
      endsAt: row['ends_at'] != null ? DateTime.parse(row['ends_at'] as String) : null,
    );
  }
}

class CtfEventDetail {
  CtfEventDetail({required this.id, required this.title, required this.description, required this.startsAt, required this.endsAt});

  final String id;
  final String title;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory CtfEventDetail.fromRow(Map<String, dynamic> row) {
    return CtfEventDetail(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      startsAt: row['starts_at'] != null ? DateTime.parse(row['starts_at'] as String) : null,
      endsAt: row['ends_at'] != null ? DateTime.parse(row['ends_at'] as String) : null,
    );
  }
}

/// Mirrors `CtfLeaderboardEntry` in `types/database.ts` -- the row shape
/// `ctf_event_leaderboard()` returns: a cross-user AGGREGATE only (total
/// score, solve count, last-solve time), never which specific challenges
/// a rival solved.
class CtfLeaderboardEntry {
  CtfLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.totalPoints,
    required this.solvedCount,
    required this.lastSolveAt,
  });

  final String userId;
  final String displayName;
  final int totalPoints;
  final int solvedCount;
  final DateTime lastSolveAt;

  factory CtfLeaderboardEntry.fromRow(Map<String, dynamic> row) {
    return CtfLeaderboardEntry(
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String,
      totalPoints: row['total_points'] as int,
      solvedCount: row['solved_count'] as int,
      lastSolveAt: DateTime.parse(row['last_solve_at'] as String),
    );
  }
}
