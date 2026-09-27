import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ctf_challenge.dart';

/// Mirrors apps/web's flag-submit.tsx: the only way this ever learns
/// correct/incorrect is the real submit_ctf_flag() RPC response -- no
/// client-side flag comparison exists anywhere in this widget.
class FlagSubmit extends StatefulWidget {
  const FlagSubmit({super.key, required this.challengeId, required this.initiallySolved});

  final String challengeId;
  final bool initiallySolved;

  @override
  State<FlagSubmit> createState() => _FlagSubmitState();
}

class _FlagSubmitState extends State<FlagSubmit> {
  final _controller = TextEditingController();
  bool _submitting = false;
  CtfSubmissionResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initiallySolved) {
      _result = CtfSubmissionResult(correct: true, pointsAwarded: 0);
    }
    // Rebuilds so the Submit button's disabled state tracks whether the
    // field is actually empty, not just its value at the last setState.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client.rpc(
        'submit_ctf_flag',
        params: {'p_challenge_id': widget.challengeId, 'p_flag': _controller.text},
      );
      final result = CtfSubmissionResult.fromRow(row as Map<String, dynamic>);
      setState(() {
        _result = result;
        if (!result.correct) _controller.clear();
      });
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null && result.correct) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Text(
          result.pointsAwarded > 0
              ? 'Correct — +${result.pointsAwarded} points. This skill\'s evidence has been recorded.'
              : 'Correct. This skill\'s evidence has been recorded.',
          style: TextStyle(color: Colors.green.shade800),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(hintText: 'ICOREPEN{...}', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_submitting || _controller.text.isEmpty) ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ],
        ),
        if (result != null && !result.correct) ...[
          const SizedBox(height: 8),
          Text('Incorrect. Try again.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}
