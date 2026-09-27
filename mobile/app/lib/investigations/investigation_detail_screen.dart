import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'investigation.dart';
import 'investigation_answers.dart';
import 'notes_pad.dart';

class InvestigationDetailScreen extends StatefulWidget {
  const InvestigationDetailScreen({super.key, required this.investigationId});

  final String investigationId;

  @override
  State<InvestigationDetailScreen> createState() => _InvestigationDetailScreenState();
}

class _InvestigationDetailScreenState extends State<InvestigationDetailScreen> {
  late Future<(Investigation, List<InvestigationArtifact>, List<InvestigationQuestion>, String)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Investigation, List<InvestigationArtifact>, List<InvestigationQuestion>, String)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final investigationRow = await client
        .from('investigations')
        .select('id, title, briefing, category, difficulty, estimated_minutes, points, passing_score')
        .eq('id', widget.investigationId)
        .eq('published', true)
        .single();
    final artifactRows = await client
        .from('investigation_artifacts')
        .select('id, artifact_type, title, content')
        .eq('investigation_id', widget.investigationId)
        .order('order_index');
    final questionRows = await client
        .from('investigation_questions_for_attempt')
        .select('question_id, question_text, question_type, choice_id, choice_text')
        .eq('investigation_id', widget.investigationId);
    final instanceRow = await client
        .from('investigation_instances')
        .select('notes')
        .eq('investigation_id', widget.investigationId)
        .eq('user_id', userId)
        .maybeSingle();

    final investigation = Investigation.fromRow(investigationRow);
    final artifacts = (artifactRows as List)
        .map((row) => InvestigationArtifact.fromRow(row as Map<String, dynamic>))
        .toList();
    final questions = groupQuestionRows((questionRows as List).cast<Map<String, dynamic>>());
    final notes = (instanceRow?['notes'] as String?) ?? '';
    return (investigation, artifacts, questions, notes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Investigation')),
      body: FutureBuilder<(Investigation, List<InvestigationArtifact>, List<InvestigationQuestion>, String)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this investigation: ${snapshot.error}'));
          }
          final (investigation, artifacts, questions, notes) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(investigation.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${investigation.category} · ${investigation.difficulty} · '
                '${investigation.estimatedMinutes} min · ${investigation.points} pts',
              ),
              if (investigation.briefing != null) ...[
                const SizedBox(height: 16),
                Text(investigation.briefing!),
              ],
              const SizedBox(height: 24),
              Text('Evidence', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...artifacts.map(
                (artifact) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    title: Text(artifact.title),
                    subtitle: Text(artifact.artifactType.replaceAll('_', ' ')),
                    initiallyExpanded: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(artifact.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              NotesPad(investigationId: investigation.id, initialNotes: notes),
              const SizedBox(height: 16),
              InvestigationAnswers(
                investigationId: investigation.id,
                passingScore: investigation.passingScore,
                questions: questions,
              ),
            ],
          );
        },
      ),
    );
  }
}
