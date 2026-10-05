import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ctf_challenge.dart';
import 'ctf_detail_screen.dart';
import 'ctf_event.dart';
import 'ctf_event_detail_screen.dart';

/// Reads the same `ctf_challenges_public` view apps/web's /ctf page does
/// (published challenges, flag hash never exposed) -- real RLS, no mock
/// data.
Future<List<CtfChallenge>> fetchCtfChallenges(SupabaseClient client) async {
  final rows = await client
      .from('ctf_challenges_public')
      .select('id, title, description, category, difficulty, points, current_points, event_id')
      .order('points');
  return (rows as List).map((row) => CtfChallenge.fromRow(row as Map<String, dynamic>)).toList();
}

/// Mirrors `/ctf/page.tsx`'s own events query -- published events only,
/// ordered by `starts_at`.
Future<List<CtfEventSummary>> fetchCtfEvents(SupabaseClient client) async {
  final rows = await client
      .from('ctf_events')
      .select('id, slug, title, starts_at, ends_at')
      .eq('published', true)
      .order('starts_at');
  return (rows as List).map((row) => CtfEventSummary.fromRow(row as Map<String, dynamic>)).toList();
}

Color _statusColor(BuildContext context, CtfEventStatus status) {
  switch (status) {
    case CtfEventStatus.upcoming:
      return Theme.of(context).colorScheme.primary;
    case CtfEventStatus.live:
      return Colors.green;
    case CtfEventStatus.ended:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

/// `/ctf`'s equivalent -- published events (live/upcoming/ended badge,
/// same `ctfEventStatus()` classification as web) above independent
/// challenges (`event_id IS NULL`). See ADR 0063.
class CtfListScreen extends StatefulWidget {
  const CtfListScreen({super.key});

  @override
  State<CtfListScreen> createState() => _CtfListScreenState();
}

class _CtfListScreenState extends State<CtfListScreen> {
  late Future<(List<CtfEventSummary>, List<CtfChallenge>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<CtfEventSummary>, List<CtfChallenge>)> _load() async {
    final client = Supabase.instance.client;
    final events = await fetchCtfEvents(client);
    final challenges = await fetchCtfChallenges(client);
    return (events, challenges);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<(List<CtfEventSummary>, List<CtfChallenge>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load challenges: ${snapshot.error}'),
                ),
              ],
            );
          }
          final (events, challenges) = snapshot.data!;
          final independentChallenges = challenges.where((c) => c.eventId == null).toList();
          return ListView(
            children: [
              if (events.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Events', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...events.map((event) {
                  final status = ctfEventStatus(event.startsAt, event.endsAt);
                  return ListTile(
                    title: Text(event.title),
                    trailing: Chip(
                      label: Text(ctfEventStatusLabel(status)),
                      backgroundColor: _statusColor(context, status).withValues(alpha: 0.15),
                      labelStyle: TextStyle(color: _statusColor(context, status)),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CtfEventDetailScreen(eventId: event.id)),
                    ),
                  );
                }),
                const Divider(height: 1),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Independent challenges', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (independentChallenges.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No independent challenges are published yet.'),
                )
              else
                ...independentChallenges.map(
                  (challenge) => Column(
                    children: [
                      ListTile(
                        title: Text(challenge.title),
                        subtitle: Text('${challenge.category} · ${challenge.difficulty}'),
                        trailing: Text('${challenge.currentPoints} pts'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CtfDetailScreen(challengeId: challenge.id)),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
