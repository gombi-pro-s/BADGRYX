import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Mirrors `types/database.ts`'s `LabCategory`/`DifficultyLevel`/
/// `CtfScoringType` unions exactly -- the same fixed value sets
/// `admin/ctf/challenge-form-fields.tsx` and `admin/ctf-events/*` render
/// as `<select>` options.
const List<String> ctfCategories = [
  'web',
  'api',
  'linux',
  'windows',
  'osint',
  'forensics',
  'crypto',
  'reverse_engineering',
  'cloud',
  'container',
  'misc',
];

const List<String> ctfDifficulties = ['beginner', 'easy', 'medium', 'hard', 'insane'];

const List<String> ctfScoringTypes = ['static', 'dynamic'];

final RegExp _slugPattern = RegExp(r'^[a-z0-9-]{3,64}$');

/// Mirrors both `admin/ctf/actions.ts`'s and `admin/ctf-events/actions.ts`'s
/// shared zod slug schema: lowercase letters, digits, hyphens, 3-64 chars.
bool isValidCtfSlug(String slug) => _slugPattern.hasMatch(slug);

/// Mirrors `hashFlag()` in `apps/web/src/lib/security/flag-hash.ts`
/// exactly: lowercase hex SHA-256, i.e. Postgres'
/// `encode(digest(flag, 'sha256'), 'hex')`. Run on-device rather than via a
/// Route Handler -- see ADR 0053 for why that's not a weaker boundary than
/// the web admin CMS's own "hash it in the Server Action" design: the
/// plaintext already exists only in the hands of the staff admin typing it,
/// on the web or here, before this ever runs.
String hashCtfFlag(String plaintext) => sha256.convert(utf8.encode(plaintext)).toString();

/// Mirrors the one cross-field rule both CTF event server actions enforce
/// beyond their per-field zod schema: `endsAt <= startsAt` is rejected.
/// Returns the exact same error message, or null when the pair is fine
/// (including when either side is absent).
String? ctfEventTimeRangeError(DateTime? startsAt, DateTime? endsAt) {
  if (startsAt != null && endsAt != null && !endsAt.isAfter(startsAt)) {
    return 'End time must be after the start time.';
  }
  return null;
}

class AdminCtfChallenge {
  AdminCtfChallenge({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.points,
    required this.published,
    required this.eventId,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final String category;
  final String difficulty;
  final int points;
  final bool published;
  final String? eventId;

  factory AdminCtfChallenge.fromRow(Map<String, dynamic> row) {
    return AdminCtfChallenge(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      category: row['category'] as String,
      difficulty: row['difficulty'] as String,
      points: row['points'] as int,
      published: row['published'] as bool,
      eventId: row['event_id'] as String?,
    );
  }
}

class AdminCtfEvent {
  AdminCtfEvent({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.scoringType,
    required this.startsAt,
    required this.endsAt,
    required this.published,
  });

  final String id;
  final String slug;
  final String title;
  final String? description;
  final String scoringType;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool published;

  factory AdminCtfEvent.fromRow(Map<String, dynamic> row) {
    return AdminCtfEvent(
      id: row['id'] as String,
      slug: row['slug'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      scoringType: row['scoring_type'] as String,
      startsAt: row['starts_at'] == null ? null : DateTime.parse(row['starts_at'] as String),
      endsAt: row['ends_at'] == null ? null : DateTime.parse(row['ends_at'] as String),
      published: row['published'] as bool,
    );
  }
}
