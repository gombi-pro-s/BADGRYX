import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _saveDebounce = Duration(seconds: 1);

/// Mirrors apps/web's notes-pad.tsx: a private, ungraded scratchpad
/// (investigation_instances.notes -- not even staff can read another
/// user's notes, per the RLS this repo's SQL tests already prove),
/// autosaved via a debounced upsert rather than an explicit save button.
class NotesPad extends StatefulWidget {
  const NotesPad({super.key, required this.investigationId, required this.initialNotes});

  final String investigationId;
  final String initialNotes;

  @override
  State<NotesPad> createState() => _NotesPadState();
}

enum _SaveStatus { idle, saving, saved, error }

class _NotesPadState extends State<NotesPad> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialNotes);
  Timer? _debounce;
  _SaveStatus _status = _SaveStatus.idle;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSave(String next) {
    setState(() => _status = _SaveStatus.idle);
    _debounce?.cancel();
    _debounce = Timer(_saveDebounce, () async {
      setState(() => _status = _SaveStatus.saving);
      try {
        final client = Supabase.instance.client;
        await client.from('investigation_instances').upsert({
          'investigation_id': widget.investigationId,
          'user_id': client.auth.currentUser!.id,
          'notes': next,
        }, onConflict: 'investigation_id,user_id');
        if (mounted) setState(() => _status = _SaveStatus.saved);
      } catch (e) {
        if (mounted) setState(() => _status = _SaveStatus.error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Your notes', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  switch (_status) {
                    _SaveStatus.saving => 'Saving...',
                    _SaveStatus.saved => 'Saved',
                    _SaveStatus.error => 'Could not save',
                    _SaveStatus.idle => '',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    color: _status == _SaveStatus.error ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Private working notes -- only you can see these, not even staff. Not graded; use '
              "them to track what you've found while you work through the evidence.",
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              onChanged: _scheduleSave,
              maxLines: 8,
              maxLength: 20000,
              decoration: const InputDecoration(
                hintText: 'e.g. domain registered 3 days before the phishing email was sent...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
