import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lab.dart';
import 'terminal_screen.dart';

/// Mirrors apps/web's lab-workspace.tsx: start guided/unguided (a plain
/// lab_instances insert -- RLS scopes it to the caller's own user_id),
/// unlock hints via the real unlock_lab_hint() RPC, and submit the flag
/// via the real submit_lab_flag() RPC. No client-side flag comparison,
/// no invented hint content -- everything shown came from a real row.
class LabWorkspace extends StatefulWidget {
  const LabWorkspace({
    super.key,
    required this.labId,
    required this.hints,
    required this.initialInstance,
    required this.hasTerminal,
  });

  final String labId;
  final List<LabHint> hints;
  final LabInstance? initialInstance;
  final bool hasTerminal;

  @override
  State<LabWorkspace> createState() => _LabWorkspaceState();
}

class _LabWorkspaceState extends State<LabWorkspace> {
  LabInstance? _instance;
  bool _starting = false;
  final Map<String, String> _unlockedContent = {};
  String? _unlockingId;
  final _flagController = TextEditingController();
  bool _submitting = false;
  bool? _correct;
  String? _error;

  @override
  void initState() {
    super.initState();
    _instance = widget.initialInstance;
    _flagController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _flagController.dispose();
    super.dispose();
  }

  Future<void> _startLab(bool guided) async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('lab_instances')
          .insert({'lab_id': widget.labId, 'user_id': client.auth.currentUser!.id, 'guided': guided, 'status': 'running'})
          .select('id, guided, status')
          .single();
      setState(() => _instance = LabInstance.fromRow(row));
    } catch (e) {
      setState(() => _error = 'Failed to start lab.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _unlockHint(LabHint hint) async {
    setState(() => _unlockingId = hint.id);
    try {
      final client = Supabase.instance.client;
      await client.rpc('unlock_lab_hint', params: {'p_lab_instance_id': _instance!.id, 'p_hint_id': hint.id});
      final row = await client.from('lab_hints').select('content').eq('id', hint.id).single();
      setState(() => _unlockedContent[hint.id] = row['content'] as String);
    } catch (e) {
      setState(() => _error = 'Failed to unlock hint.');
    } finally {
      if (mounted) setState(() => _unlockingId = null);
    }
  }

  Future<void> _submitFlag() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client.rpc(
        'submit_lab_flag',
        params: {'p_lab_instance_id': _instance!.id, 'p_flag': _flagController.text},
      );
      final correct = submissionCorrect(row as Map<String, dynamic>);
      setState(() {
        _correct = correct;
        if (!correct) _flagController.clear();
      });
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instance = _instance;
    if (instance == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Start this lab', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'Guided records "guided_lab" evidence and unlocks hints. Unguided records '
                '"unguided_lab" evidence (independent demonstration) but has no hints available.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton(
                    onPressed: _starting ? null : () => _startLab(true),
                    child: Text(_starting ? 'Starting...' : 'Start guided'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _starting ? null : () => _startLab(false),
                    child: Text(_starting ? 'Starting...' : 'Start unguided'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_correct == true || instance.status == 'stopped') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hasTerminal) _OpenTerminalButton(labInstanceId: instance.id),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Correct flag. Lab completed'
              '${instance.guided ? " (guided)" : " (unguided — independent demonstration recorded)"}.',
              style: TextStyle(color: Colors.green.shade800),
            ),
          ),
        ],
      );
    }

    final sortedHints = [...widget.hints]..sort((a, b) => a.level.compareTo(b.level));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.hasTerminal) _OpenTerminalButton(labInstanceId: instance.id),
        if (instance.guided && sortedHints.isNotEmpty) ...[
          const Text('Hints', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...sortedHints.map((hint) {
            final unlocked = _unlockedContent[hint.id];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: unlocked != null
                    ? Text(unlocked)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Level ${hint.level} hint (${hint.pointCost} pts)'),
                          TextButton(
                            onPressed: _unlockingId == hint.id ? null : () => _unlockHint(hint),
                            child: Text(_unlockingId == hint.id ? 'Unlocking...' : 'Unlock'),
                          ),
                        ],
                      ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        const Text('Submit flag', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _flagController,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(hintText: 'ICOREPEN{...}', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_submitting || _flagController.text.isEmpty) ? null : _submitFlag,
              child: _submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit'),
            ),
          ],
        ),
        if (_correct == false) ...[
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

class _OpenTerminalButton extends StatelessWidget {
  const _OpenTerminalButton({required this.labInstanceId});

  final String labInstanceId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.terminal),
        label: const Text('Open terminal'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TerminalScreen(labInstanceId: labInstanceId)),
        ),
      ),
    );
  }
}
