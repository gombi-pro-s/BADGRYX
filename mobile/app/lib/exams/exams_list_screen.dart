import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'exam.dart';
import 'exam_detail_screen.dart';

/// Mirrors apps/web's /exams list page: published is_exam quizzes plus
/// this user's own quiz_attempts for the passed/attempts-used display.
Future<(List<Exam>, Set<String>, Map<String, int>)> fetchExams(SupabaseClient client, String userId) async {
  final examRows = await client
      .from('quizzes')
      .select('id, title, passing_score, max_attempts, time_limit_minutes')
      .eq('is_exam', true)
      .eq('published', true)
      .order('title');
  final attemptRows = await client.from('quiz_attempts').select('quiz_id, passed').eq('user_id', userId);

  final exams = (examRows as List).map((row) => Exam.fromRow(row as Map<String, dynamic>)).toList();
  final passedQuizIds = (attemptRows as List)
      .where((row) => row['passed'] == true)
      .map((row) => row['quiz_id'] as String)
      .toSet();
  final attemptCounts = <String, int>{};
  for (final row in attemptRows) {
    final quizId = row['quiz_id'] as String;
    attemptCounts[quizId] = (attemptCounts[quizId] ?? 0) + 1;
  }
  return (exams, passedQuizIds, attemptCounts);
}

class ExamsListScreen extends StatefulWidget {
  const ExamsListScreen({super.key});

  @override
  State<ExamsListScreen> createState() => _ExamsListScreenState();
}

class _ExamsListScreenState extends State<ExamsListScreen> {
  late Future<(List<Exam>, Set<String>, Map<String, int>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Exam>, Set<String>, Map<String, int>)> _load() {
    final client = Supabase.instance.client;
    return fetchExams(client, client.auth.currentUser!.id);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<(List<Exam>, Set<String>, Map<String, int>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(padding: const EdgeInsets.all(24), child: Text('Could not load exams: ${snapshot.error}')),
              ],
            );
          }
          final (exams, passedQuizIds, attemptCounts) = snapshot.data!;
          if (exams.isEmpty) {
            return ListView(
              children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No exams are published yet.')),
              ],
            );
          }
          return ListView.separated(
            itemCount: exams.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final exam = exams[index];
              final used = attemptCounts[exam.id] ?? 0;
              final parts = <String>['Pass at ${exam.passingScore}%'];
              if (exam.timeLimitMinutes != null) parts.add('${exam.timeLimitMinutes} min');
              if (exam.maxAttempts != null) parts.add('$used/${exam.maxAttempts} attempts used');
              return ListTile(
                title: Text(exam.title),
                subtitle: Text(parts.join(' · ')),
                trailing: passedQuizIds.contains(exam.id)
                    ? const Text('Passed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
                    : null,
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamDetailScreen(quizId: exam.id))),
              );
            },
          );
        },
      ),
    );
  }
}
