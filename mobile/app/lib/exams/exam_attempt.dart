import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'exam.dart';

const Map<String, String> _hintPolicyCopy = {
  'none': 'No hints — exam conditions. Answer from what you know.',
  'limited': 'Limited hints are available for this exam.',
  'full': 'Full hints are available for this exam.',
};

/// Mirrors apps/web's exam-attempt.tsx: a real countdown timer
/// (client-side only -- the same honest, documented limitation as the
/// web app: no server-side exam-session record, so a refresh restarts
/// the clock), single/multi-choice answer collection, and grading
/// exclusively through the real submit_quiz_attempt() RPC.
class ExamAttempt extends StatefulWidget {
  const ExamAttempt({
    super.key,
    required this.quizId,
    required this.title,
    required this.passingScore,
    required this.timeLimitMinutes,
    required this.hintPolicy,
    required this.questions,
    required this.attemptsRemaining,
  });

  final String quizId;
  final String title;
  final num passingScore;
  final int? timeLimitMinutes;
  final String hintPolicy;
  final List<ExamQuestion> questions;
  final int? attemptsRemaining;

  @override
  State<ExamAttempt> createState() => _ExamAttemptState();
}

class _ExamAttemptState extends State<ExamAttempt> {
  final Map<String, List<String>> _answers = {};
  ({bool passed, num score})? _result;
  String? _error;
  bool _submitting = false;
  Timer? _timer;
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    if (widget.timeLimitMinutes != null) {
      _secondsLeft = widget.timeLimitMinutes! * 60;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_result != null) {
        timer.cancel();
        return;
      }
      if ((_secondsLeft ?? 0) <= 0) {
        timer.cancel();
        _submit();
        return;
      }
      setState(() => _secondsLeft = _secondsLeft! - 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final payload = <String, List<String>>{};
      for (final q in widget.questions) {
        payload[q.questionId] = _answers[q.questionId] ?? [];
      }
      final row = await Supabase.instance.client.rpc(
        'submit_quiz_attempt',
        params: {'p_quiz_id': widget.quizId, 'p_answers': payload},
      );
      final data = row as Map<String, dynamic>;
      setState(() => _result = (passed: data['passed'] as bool, score: data['score'] as num));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (result.passed ? Colors.green : Colors.red).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (result.passed ? Colors.green : Colors.red).withValues(alpha: 0.3)),
        ),
        child: Text(
          '${result.passed ? "Passed" : "Not yet"} — ${result.score}% (passing: ${widget.passingScore}%)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: result.passed ? Colors.green.shade800 : Colors.red.shade800,
          ),
        ),
      );
    }

    if (widget.attemptsRemaining != null && widget.attemptsRemaining! <= 0) {
      return const Text("You've used all your attempts for this exam.");
    }

    final secondsLeft = _secondsLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        _hintPolicyCopy[widget.hintPolicy] ?? '',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (secondsLeft != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: secondsLeft <= 60 ? Colors.red.withValues(alpha: 0.1) : Colors.transparent,
                      border: Border.all(
                        color: secondsLeft <= 60 ? Colors.red.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formatExamTime(secondsLeft),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: secondsLeft <= 60 ? Colors.red.shade800 : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final q in widget.questions) ...[
          Text('${q.questionText} (${q.points} ${q.points == 1 ? "point" : "points"})'),
          const SizedBox(height: 4),
          if (q.questionType == 'short_answer')
            const Text("This question type isn't auto-gradable yet.", style: TextStyle(fontSize: 12))
          else if (q.questionType == 'multi_choice')
            ...q.choices.map(
              (choice) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(choice.choiceText),
                value: (_answers[q.questionId] ?? []).contains(choice.choiceId),
                onChanged: (_) => setState(
                  () => _answers[q.questionId] = toggleChoice(_answers[q.questionId] ?? [], choice.choiceId, multi: true),
                ),
              ),
            )
          else
            RadioGroup<String>(
              groupValue: (_answers[q.questionId] ?? []).isEmpty ? null : _answers[q.questionId]!.first,
              onChanged: (value) => setState(
                () => _answers[q.questionId] = toggleChoice(_answers[q.questionId] ?? [], value!, multi: false),
              ),
              child: Column(
                children: q.choices
                    .map(
                      (choice) => RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(choice.choiceText),
                        value: choice.choiceId,
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Submitting...' : 'Submit exam'),
        ),
      ],
    );
  }
}
