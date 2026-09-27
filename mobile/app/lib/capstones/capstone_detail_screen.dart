import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'capstone.dart';

class CapstoneDetailScreen extends StatefulWidget {
  const CapstoneDetailScreen({super.key, required this.capstoneId});

  final String capstoneId;

  @override
  State<CapstoneDetailScreen> createState() => _CapstoneDetailScreenState();
}

class _CapstoneDetailScreenState extends State<CapstoneDetailScreen> {
  late Future<(Capstone, List<String>, List<String>, List<CapstoneSubmission>)> _future;
  final _reportController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  Future<(Capstone, List<String>, List<String>, List<CapstoneSubmission>)> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final capstoneRow = await client
        .from('capstones')
        .select('id, title, description, report_required')
        .eq('id', widget.capstoneId)
        .eq('published', true)
        .single();
    final skillLinkRows = await client.from('capstone_skills').select('skill_id').eq('capstone_id', widget.capstoneId);
    final labLinkRows = await client.from('capstone_labs').select('lab_id').eq('capstone_id', widget.capstoneId);
    final submissionRows = await client
        .from('capstone_submissions')
        .select('status, reviewer_notes, submitted_at')
        .eq('capstone_id', widget.capstoneId)
        .eq('user_id', userId)
        .order('submitted_at', ascending: false);

    final skillIds = (skillLinkRows as List).map((r) => r['skill_id'] as String).toList();
    final labIds = (labLinkRows as List).map((r) => r['lab_id'] as String).toList();

    final skillNames = skillIds.isEmpty
        ? <String>[]
        : ((await client.from('skills').select('name').inFilter('id', skillIds)) as List)
            .map((r) => r['name'] as String)
            .toList();
    final labTitles = labIds.isEmpty
        ? <String>[]
        : ((await client.from('labs').select('title').inFilter('id', labIds)) as List)
            .map((r) => r['title'] as String)
            .toList();

    final capstone = Capstone.fromRow(capstoneRow);
    final submissions = (submissionRows as List)
        .map((row) => CapstoneSubmission.fromRow(row as Map<String, dynamic>))
        .toList();
    return (capstone, skillNames, labTitles, submissions);
  }

  Future<void> _submit() async {
    if (_reportController.text.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      await client.from('capstone_submissions').insert({
        'capstone_id': widget.capstoneId,
        'user_id': client.auth.currentUser!.id,
        'report_content': _reportController.text,
      });
      setState(() {
        _reportController.clear();
        _future = _load();
      });
    } catch (e) {
      setState(() => _error = 'Failed to submit report.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capstone')),
      body: FutureBuilder<(Capstone, List<String>, List<String>, List<CapstoneSubmission>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this capstone: ${snapshot.error}'));
          }
          final (capstone, skillNames, labTitles, submissions) = snapshot.data!;
          final alreadyPassed = submissions.isNotEmpty && submissions.first.status == 'passed';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(capstone.title, style: Theme.of(context).textTheme.headlineSmall),
              if (capstone.description != null) ...[
                const SizedBox(height: 8),
                Text(capstone.description!),
              ],
              if (skillNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Skills demonstrated on a pass', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: skillNames.map((name) => Chip(label: Text(name))).toList(),
                ),
              ],
              if (labTitles.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Related labs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: labTitles.map((title) => Chip(label: Text(title))).toList(),
                ),
              ],
              if (submissions.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Your submissions', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final s in submissions)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${s.submittedAt.year}-${s.submittedAt.month.toString().padLeft(2, '0')}-${s.submittedAt.day.toString().padLeft(2, '0')}',
                              ),
                              Text(
                                capstoneStatusLabel[s.status] ?? s.status,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (s.reviewerNotes != null) ...[
                            const SizedBox(height: 4),
                            Text('Reviewer notes: ${s.reviewerNotes}', style: const TextStyle(fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              if (alreadyPassed)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Text("You've already passed this capstone."),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          submissions.isNotEmpty ? 'Submit again' : 'Submit your report',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reportController,
                          maxLines: 10,
                          maxLength: 20000,
                          decoration: const InputDecoration(
                            hintText: "Write your report: what you did, how you did it, what you found, "
                                "and how you'd remediate it.",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: Text(_submitting ? 'Submitting...' : 'Submit report'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
