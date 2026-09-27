import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'investigation.dart';
import 'investigation_detail_screen.dart';

/// Mirrors apps/web's /investigate list page exactly, including the
/// "highest score wins, not most recent" best-submission logic.
Future<(List<Investigation>, Map<String, BestSubmission>)> fetchInvestigations(
  SupabaseClient client,
  String userId,
) async {
  final investigationRows = await client
      .from('investigations')
      .select('id, title, briefing, category, difficulty, estimated_minutes, points, passing_score')
      .eq('published', true)
      .order('title');
  final submissionRows = await client
      .from('investigation_submissions')
      .select('investigation_id, passed, score')
      .eq('user_id', userId);

  final investigations = (investigationRows as List)
      .map((row) => Investigation.fromRow(row as Map<String, dynamic>))
      .toList();
  final best = bestSubmissionByInvestigation((submissionRows as List).cast<Map<String, dynamic>>());
  return (investigations, best);
}

class InvestigationsListScreen extends StatefulWidget {
  const InvestigationsListScreen({super.key});

  @override
  State<InvestigationsListScreen> createState() => _InvestigationsListScreenState();
}

class _InvestigationsListScreenState extends State<InvestigationsListScreen> {
  late Future<(List<Investigation>, Map<String, BestSubmission>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Investigation>, Map<String, BestSubmission>)> _load() {
    final client = Supabase.instance.client;
    return fetchInvestigations(client, client.auth.currentUser!.id);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<(List<Investigation>, Map<String, BestSubmission>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load investigations: ${snapshot.error}'),
                ),
              ],
            );
          }
          final (investigations, best) = snapshot.data!;
          if (investigations.isEmpty) {
            return ListView(
              children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No investigations are published yet.')),
              ],
            );
          }
          return ListView.separated(
            itemCount: investigations.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final investigation = investigations[index];
              final badge = best[investigation.id];
              return ListTile(
                title: Text(investigation.title),
                subtitle: Text(
                  '${investigation.category} · ${investigation.difficulty} · '
                  '${investigation.estimatedMinutes} min · ${investigation.points} pts',
                ),
                trailing: badge == null
                    ? null
                    : Text(
                        badge.passed ? 'Solved' : 'Best: ${badge.score}%',
                        style: TextStyle(
                          color: badge.passed ? Colors.green.shade700 : Colors.amber.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => InvestigationDetailScreen(investigationId: investigation.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
