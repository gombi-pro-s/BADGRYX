import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'investigation.dart';

/// Mirrors apps/web's investigation-answers.tsx: real, deterministic,
/// server-side grading via submit_investigation_answers() -- this widget
/// never decides pass/fail itself, only renders whatever the RPC returns.
class InvestigationAnswers extends StatefulWidget {
  const InvestigationAnswers({
    super.key,
    required this.investigationId,
    required this.passingScore,
    required this.questions,
  });

  final String investigationId;
  final int passingScore;
  final List<InvestigationQuestion> questions;

  @override
  State<InvestigationAnswers> createState() => _InvestigationAnswersState();
}

class _InvestigationAnswersState extends State<InvestigationAnswers> {
  final Map<String, String> _choiceAnswers = {};
  final Map<String, String> _textAnswers = {};
  bool _submitting = false;
  String? _error;
  ({bool passed, int score})? _result;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final payload = buildAnswersPayload(widget.questions, _choiceAnswers, _textAnswers);
      final row = await Supabase.instance.client.rpc(
        'submit_investigation_answers',
        params: {'p_investigation_id': widget.investigationId, 'p_answers': payload},
      );
      final data = row as Map<String, dynamic>;
      setState(() => _result = (passed: data['passed'] as bool, score: data['score'] as int));
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
          color: (result.passed ? Colors.green : Colors.amber).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (result.passed ? Colors.green : Colors.amber).withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.passed ? "Case solved" : "Not yet"} — ${result.score}% '
              '(passing: ${widget.passingScore}%)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: result.passed ? Colors.green.shade800 : Colors.amber.shade900,
              ),
            ),
            if (!result.passed) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _result = null),
                child: const Text('Review the evidence again and retry'),
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your findings', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final q in widget.questions) ...[
              Text(q.questionText),
              const SizedBox(height: 4),
              if (q.questionType == 'multiple_choice')
                RadioGroup<String>(
                  groupValue: _choiceAnswers[q.questionId],
                  onChanged: (value) => setState(() => _choiceAnswers[q.questionId] = value!),
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
                )
              else
                TextField(
                  decoration: const InputDecoration(hintText: 'Your answer', border: OutlineInputBorder()),
                  onChanged: (value) => _textAnswers[q.questionId] = value,
                ),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting...' : 'Submit findings'),
            ),
          ],
        ),
      ),
    );
  }
}
