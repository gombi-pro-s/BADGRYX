import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'exam.dart';
import 'exam_attempt.dart';

class _ExamMeta {
  _ExamMeta({
    required this.title,
    required this.passingScore,
    required this.maxAttempts,
    required this.timeLimitMinutes,
    required this.hintPolicy,
  });

  final String title;
  final num passingScore;
  final int? maxAttempts;
  final int? timeLimitMinutes;
  final String hintPolicy;
}

class _PriorAttempt {
  _PriorAttempt({required this.score, required this.passed, required this.submittedAt});

  final num score;
  final bool passed;
  final DateTime submittedAt;
}

class ExamDetailScreen extends StatefulWidget {
  const ExamDetailScreen({super.key, required this.quizId});

  final String quizId;

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  late Future<(_ExamMeta, List<ExamQuestion>, List<_PriorAttempt>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(_ExamMeta, List<ExamQuestion>, List<_PriorAttempt>)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final rows = await client
        .from('quiz_questions_for_attempt')
        .select(
          'quiz_id, title, passing_score, max_attempts, is_exam, time_limit_minutes, hint_policy, '
          'question_id, question_text, question_type, order_index, points, choice_id, choice_text, choice_order_index',
        )
        .eq('quiz_id', widget.quizId)
        .order('order_index');
    final attemptRows = await client
        .from('quiz_attempts')
        .select('score, passed, submitted_at')
        .eq('quiz_id', widget.quizId)
        .eq('user_id', userId)
        .order('submitted_at', ascending: false);

    final firstRow = (rows as List).first as Map<String, dynamic>;
    final meta = _ExamMeta(
      title: firstRow['title'] as String,
      passingScore: firstRow['passing_score'] as num,
      maxAttempts: firstRow['max_attempts'] as int?,
      timeLimitMinutes: firstRow['time_limit_minutes'] as int?,
      hintPolicy: firstRow['hint_policy'] as String,
    );
    final questions = groupExamQuestionRows(rows.cast<Map<String, dynamic>>());
    final priorAttempts = (attemptRows as List)
        .map(
          (row) => _PriorAttempt(
            score: row['score'] as num,
            passed: row['passed'] as bool,
            submittedAt: DateTime.parse(row['submitted_at'] as String),
          ),
        )
        .toList();
    return (meta, questions, priorAttempts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam')),
      body: FutureBuilder<(_ExamMeta, List<ExamQuestion>, List<_PriorAttempt>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this exam: ${snapshot.error}'));
          }
          final (meta, questions, priorAttempts) = snapshot.data!;
          final alreadyPassed = priorAttempts.any((a) => a.passed);
          final remaining = attemptsRemaining(meta.maxAttempts, priorAttempts.length);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(meta.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Passing score: ${meta.passingScore}%'
                '${meta.maxAttempts != null ? " · ${meta.maxAttempts} attempts allowed" : ""}'
                '${meta.timeLimitMinutes != null ? " · ${meta.timeLimitMinutes} minute time limit" : ""}',
              ),
              if (priorAttempts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your previous attempts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        const SizedBox(height: 4),
                        for (final a in priorAttempts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${a.submittedAt.year}-${a.submittedAt.month.toString().padLeft(2, '0')}-${a.submittedAt.day.toString().padLeft(2, '0')}',
                                ),
                                Text(
                                  '${a.score}% — ${a.passed ? "Passed" : "Failed"}',
                                  style: TextStyle(color: a.passed ? Colors.green.shade700 : Colors.red.shade700),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (alreadyPassed)
                const Text("You've already passed this exam.")
              else
                ExamAttempt(
                  quizId: widget.quizId,
                  title: meta.title,
                  passingScore: meta.passingScore,
                  timeLimitMinutes: meta.timeLimitMinutes,
                  hintPolicy: meta.hintPolicy,
                  questions: questions,
                  attemptsRemaining: remaining,
                ),
            ],
          );
        },
      ),
    );
  }
}
