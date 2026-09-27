import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ctf_challenge.dart';
import 'ctf_detail_screen.dart';

/// Reads the same `ctf_challenges_public` view apps/web's /ctf page does
/// (published challenges, flag hash never exposed) -- real RLS, no mock
/// data.
Future<List<CtfChallenge>> fetchCtfChallenges(SupabaseClient client) async {
  final rows = await client.from('ctf_challenges_public').select('id, title, description, category, difficulty, points').order('points');
  return (rows as List).map((row) => CtfChallenge.fromRow(row as Map<String, dynamic>)).toList();
}

class CtfListScreen extends StatefulWidget {
  const CtfListScreen({super.key});

  @override
  State<CtfListScreen> createState() => _CtfListScreenState();
}

class _CtfListScreenState extends State<CtfListScreen> {
  late Future<List<CtfChallenge>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchCtfChallenges(Supabase.instance.client);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = fetchCtfChallenges(Supabase.instance.client);
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<List<CtfChallenge>>(
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
                  child: Text('Could not load challenges: ${snapshot.error}'),
                ),
              ],
            );
          }
          final challenges = snapshot.data ?? const [];
          if (challenges.isEmpty) {
            return ListView(
              children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No CTF challenges are published yet.')),
              ],
            );
          }
          return ListView.separated(
            itemCount: challenges.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final challenge = challenges[index];
              return ListTile(
                title: Text(challenge.title),
                subtitle: Text('${challenge.category} · ${challenge.difficulty}'),
                trailing: Text('${challenge.points} pts'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CtfDetailScreen(challengeId: challenge.id)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
