import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ctf_challenge.dart';
import 'flag_submit.dart';

class CtfDetailScreen extends StatefulWidget {
  const CtfDetailScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  State<CtfDetailScreen> createState() => _CtfDetailScreenState();
}

class _CtfDetailScreenState extends State<CtfDetailScreen> {
  late Future<(CtfChallenge, bool)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(CtfChallenge, bool)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final challengeRow = await client
        .from('ctf_challenges_public')
        .select('id, title, description, category, difficulty, points')
        .eq('id', widget.challengeId)
        .single();
    final solvedRow = await client
        .from('ctf_submissions')
        .select('id')
        .eq('challenge_id', widget.challengeId)
        .eq('user_id', userId)
        .eq('correct', true)
        .maybeSingle();
    return (CtfChallenge.fromRow(challengeRow), solvedRow != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Challenge')),
      body: FutureBuilder<(CtfChallenge, bool)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this challenge: ${snapshot.error}'));
          }
          final (challenge, solved) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(challenge.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${challenge.category} · ${challenge.difficulty} · ${challenge.points} pts'),
              if (challenge.description != null) ...[
                const SizedBox(height: 16),
                Text(challenge.description!),
              ],
              const SizedBox(height: 24),
              FlagSubmit(challengeId: challenge.id, initiallySolved: solved),
            ],
          );
        },
      ),
    );
  }
}
