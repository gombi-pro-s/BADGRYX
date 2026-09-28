import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab.dart';
import 'lab_workspace.dart';

class LabDetailScreen extends StatefulWidget {
  const LabDetailScreen({super.key, required this.labId});

  final String labId;

  @override
  State<LabDetailScreen> createState() => _LabDetailScreenState();
}

class _LabDetailScreenState extends State<LabDetailScreen> {
  late Future<(Lab, List<LabHint>, LabInstance?)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Lab, List<LabHint>, LabInstance?)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final labRow = await client
        .from('labs')
        .select('id, title, description, category, difficulty, points, has_terminal')
        .eq('id', widget.labId)
        .eq('published', true)
        .single();
    final hintRows = await client.from('lab_hints').select('id, level, point_cost').eq('lab_id', widget.labId);
    final instanceRows = await client
        .from('lab_instances')
        .select('id, guided, status')
        .eq('lab_id', widget.labId)
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .limit(1);

    final lab = Lab.fromRow(labRow);
    final hints = (hintRows as List).map((row) => LabHint.fromRow(row as Map<String, dynamic>)).toList();
    final instances = instanceRows as List;
    final instance = instances.isEmpty ? null : LabInstance.fromRow(instances.first as Map<String, dynamic>);
    return (lab, hints, instance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lab')),
      body: FutureBuilder<(Lab, List<LabHint>, LabInstance?)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this lab: ${snapshot.error}'));
          }
          final (lab, hints, instance) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(lab.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${lab.category} · ${lab.difficulty} · ${lab.points} pts'),
              if (lab.description != null) ...[
                const SizedBox(height: 16),
                Text(lab.description!),
              ],
              if (lab.hasTerminal) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'This lab has a real interactive terminal environment -- start the lab below, '
                    'then tap "Open terminal" to work through it. Command-history recall (up/down '
                    'arrow) is web-only; everything else, including flag submission and scoring, is '
                    'fully real and recorded to your Skill Graph.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    "This lab doesn't have an interactive terminal environment yet. Flag "
                    'submission and scoring below are fully real and recorded to your Skill Graph.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              LabWorkspace(labId: lab.id, hints: hints, initialInstance: instance, hasTerminal: lab.hasTerminal),
            ],
          );
        },
      ),
    );
  }
}
