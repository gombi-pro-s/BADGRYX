import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ctf_challenge.dart';
import 'ctf_detail_screen.dart';
import 'ctf_event.dart';

/// Mirrors `/ctf/events/[eventId]/page.tsx` -- the event's own
/// challenges (ordered by points, each showing `current_points` the same
/// way the flat list does) alongside `ctf_event_leaderboard()`'s
/// cross-user aggregate, with a ticking status banner matching
/// `event-status-banner.tsx`. See ADR 0063.
class CtfEventDetailScreen extends StatefulWidget {
  const CtfEventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<CtfEventDetailScreen> createState() => _CtfEventDetailScreenState();
}

class _CtfEventDetailScreenState extends State<CtfEventDetailScreen> {
  late Future<(CtfEventDetail, List<CtfChallenge>, Set<String>, List<CtfLeaderboardEntry>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(CtfEventDetail, List<CtfChallenge>, Set<String>, List<CtfLeaderboardEntry>)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final eventRow = await client
        .from('ctf_events')
        .select('id, title, description, starts_at, ends_at')
        .eq('id', widget.eventId)
        .single();
    final challengeRows = await client
        .from('ctf_challenges_public')
        .select('id, title, description, category, difficulty, points, current_points, event_id')
        .eq('event_id', widget.eventId)
        .order('points');
    final solvedRows = await client.from('ctf_submissions').select('challenge_id').eq('user_id', userId).eq('correct', true);
    final leaderboardRows = await client.rpc('ctf_event_leaderboard', params: {'p_event_id': widget.eventId});

    return (
      CtfEventDetail.fromRow(eventRow),
      (challengeRows as List).map((row) => CtfChallenge.fromRow(row as Map<String, dynamic>)).toList(),
      (solvedRows as List).map((row) => (row as Map<String, dynamic>)['challenge_id'] as String).toSet(),
      (leaderboardRows as List).map((row) => CtfLeaderboardEntry.fromRow(row as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CTF Event')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<(CtfEventDetail, List<CtfChallenge>, Set<String>, List<CtfLeaderboardEntry>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(child: Text('Could not load this event: ${snapshot.error}'));
            }
            final (event, challenges, solvedIds, leaderboard) = snapshot.data!;
            final currentUserId = Supabase.instance.client.auth.currentUser!.id;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
                if (event.description != null) ...[
                  const SizedBox(height: 4),
                  Text(event.description!),
                ],
                const SizedBox(height: 12),
                _EventStatusBanner(startsAt: event.startsAt, endsAt: event.endsAt),
                const SizedBox(height: 24),
                Text('Challenges', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (challenges.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No challenges published yet.'),
                  )
                else
                  Card(
                    child: Column(
                      children: challenges.map((challenge) {
                        return ListTile(
                          title: Text(challenge.title),
                          subtitle: Text('${challenge.category} · ${challenge.difficulty} · ${challenge.currentPoints} pts'),
                          trailing: solvedIds.contains(challenge.id)
                              ? Text('Solved', style: TextStyle(color: Theme.of(context).colorScheme.primary))
                              : null,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CtfDetailScreen(challengeId: challenge.id)),
                            );
                            await _refresh();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Leaderboard', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (leaderboard.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No solves yet -- be the first.'),
                  )
                else
                  Card(
                    child: Column(
                      children: leaderboard.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        final isMe = row.userId == currentUserId;
                        return Container(
                          color: isMe ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
                          child: ListTile(
                            dense: true,
                            leading: Text('#${index + 1}'),
                            title: Text(row.displayName),
                            trailing: Text('${row.totalPoints}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Mirrors `event-status-banner.tsx` exactly: a 1s ticking timer, nothing
/// rendered at all when the event has no time window, and no render
/// until the first real tick (avoids a server/client clock mismatch on
/// first paint -- here, just avoids showing a stale duration before the
/// timer's first callback).
class _EventStatusBanner extends StatefulWidget {
  const _EventStatusBanner({required this.startsAt, required this.endsAt});

  final DateTime? startsAt;
  final DateTime? endsAt;

  @override
  State<_EventStatusBanner> createState() => _EventStatusBannerState();
}

class _EventStatusBannerState extends State<_EventStatusBanner> {
  Timer? _timer;
  DateTime? _now;

  @override
  void initState() {
    super.initState();
    if (widget.startsAt != null || widget.endsAt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startsAt == null && widget.endsAt == null) return const SizedBox.shrink();
    final now = _now;
    if (now == null) return const SizedBox.shrink();

    final status = ctfEventStatus(widget.startsAt, widget.endsAt, now: now);
    final colors = Theme.of(context).colorScheme;

    if (status == CtfEventStatus.upcoming) {
      return _banner('Starts in ${formatCtfEventDuration(widget.startsAt!.difference(now))}', colors.primary);
    }
    if (status == CtfEventStatus.ended) {
      return _banner('Ended', colors.onSurfaceVariant);
    }
    if (widget.endsAt != null) {
      return _banner('Live -- ends in ${formatCtfEventDuration(widget.endsAt!.difference(now))}', Colors.green);
    }
    return _banner('Live', Colors.green);
  }

  Widget _banner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
