import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab.dart';
import 'lab_detail_screen.dart';

/// Mirrors apps/web's /labs page: published labs plus this user's own
/// lab_progress ("Completed" badge), real RLS-scoped reads.
Future<(List<Lab>, Set<String>)> fetchLabs(SupabaseClient client, String userId) async {
  final labRows = await client
      .from('labs')
      .select('id, title, description, category, difficulty, points, has_terminal')
      .eq('published', true)
      .order('title');
  final progressRows = await client.from('lab_progress').select('lab_id, status').eq('user_id', userId);

  final completedLabIds = (progressRows as List)
      .where((row) => row['status'] == 'completed')
      .map((row) => row['lab_id'] as String)
      .toSet();
  final labs = (labRows as List).map((row) => Lab.fromRow(row as Map<String, dynamic>)).toList();
  return (labs, completedLabIds);
}

class LabsListScreen extends StatefulWidget {
  const LabsListScreen({super.key});

  @override
  State<LabsListScreen> createState() => _LabsListScreenState();
}

class _LabsListScreenState extends State<LabsListScreen> {
  late Future<(List<Lab>, Set<String>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Lab>, Set<String>)> _load() {
    final client = Supabase.instance.client;
    return fetchLabs(client, client.auth.currentUser!.id);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<(List<Lab>, Set<String>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(padding: const EdgeInsets.all(24), child: Text('Could not load labs: ${snapshot.error}')),
              ],
            );
          }
          final (labs, completedLabIds) = snapshot.data!;
          if (labs.isEmpty) {
            return ListView(
              children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No labs are published yet.')),
              ],
            );
          }
          return ListView.separated(
            itemCount: labs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final lab = labs[index];
              return ListTile(
                title: Text(lab.title),
                subtitle: Text('${lab.category} · ${lab.difficulty} · ${lab.points} pts'),
                trailing: completedLabIds.contains(lab.id)
                    ? const Text('Completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
                    : null,
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LabDetailScreen(labId: lab.id))),
              );
            },
          );
        },
      ),
    );
  }
}
