import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../mentor/mentor_screen.dart';
import 'report.dart';

/// Mirrors reports/page.tsx + [reportId]/page.tsx + actions.ts: a real
/// pentest-report/methodology-write-up practice pillar, reviewed by the
/// AI Mentor only -- separate from a capstone's reviewed submission, and
/// never affecting the Skill Graph. Plain RLS-scoped Postgrest
/// list/create/edit/delete, no Route Handler needed.
///
/// "Ask Mentor to review" opens the existing general-mode Mentor screen
/// rather than deep-linking into `review_report`/`review_methodology`
/// (`/mentor?contextType=report&contextId=...&mode=...` on web) -- mobile
/// Mentor is still general-modes-only (ADR 0034's named gap), and this
/// screen doesn't extend that; a user can still ask for an Explain/Hint/
/// Teach/Analyze-a-failure style review, just not the report-specific
/// lens yet. See ADR 0052.
Future<List<Report>> fetchReports(SupabaseClient client, String userId) async {
  final rows = await client
      .from('reports')
      .select('id, title, kind, content_markdown, updated_at')
      .eq('user_id', userId)
      .order('updated_at', ascending: false);
  return (rows as List).map((row) => Report.fromRow(row as Map<String, dynamic>)).toList();
}

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  late Future<List<Report>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Report>> _load() {
    final client = Supabase.instance.client;
    return fetchReports(client, client.auth.currentUser!.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _openForm({String? reportId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReportFormScreen(reportId: reportId)),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'New report',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Report>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load reports: ${snapshot.error}'));
            }
            final reports = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Write a pentest report or a methodology write-up and ask the AI Mentor to critique it. '
                  "This is practice; it's separate from a capstone's reviewed submission and never affects "
                  'your Skill Graph.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (reports.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No reports yet. Write your first one with the + button.'),
                  )
                else
                  ...reports.map((report) {
                    return Card(
                      child: ListTile(
                        title: Text(report.title),
                        trailing: Chip(label: Text(reportKindLabel(report.kind))),
                        onTap: () => _openForm(reportId: report.id),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Create when `reportId` is null, edit otherwise -- same reasoning as
/// every other combined create/edit screen in this app (Flutter
/// navigation makes one form-with-optional-id the natural unit, unlike
/// the web's two separate pages).
class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key, this.reportId});

  final String? reportId;

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _kind = 'pentest_report';
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  bool get _isEditing => widget.reportId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('reports')
          .select('id, title, kind, content_markdown')
          .eq('id', widget.reportId!)
          .single();
      _titleController.text = row['title'] as String;
      _contentController.text = row['content_markdown'] as String? ?? '';
      setState(() {
        _kind = row['kind'] as String;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this report.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'Title and content are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      if (_isEditing) {
        await client
            .from('reports')
            .update({'title': title, 'kind': _kind, 'content_markdown': content})
            .eq('id', widget.reportId!);
      } else {
        await client.from('reports').insert({
          'user_id': client.auth.currentUser!.id,
          'title': title,
          'kind': _kind,
          'content_markdown': content,
        });
      }
      _changed = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = _isEditing ? 'Could not save changes.' : 'Could not create the report.';
        _saving = false;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.from('reports').delete().eq('id', widget.reportId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not delete this report.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit report' : 'New report'),
          actions: _isEditing
              ? [
                  IconButton(
                    icon: const Icon(Icons.smart_toy_outlined),
                    tooltip: 'Ask Mentor to review',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MentorScreen()),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _confirmDelete),
                ]
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Kind'),
                    items: const [
                      DropdownMenuItem(value: 'pentest_report', child: Text('Pentest report')),
                      DropdownMenuItem(value: 'methodology', child: Text('Methodology write-up')),
                    ],
                    onChanged: (value) => setState(() => _kind = value ?? _kind),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contentController,
                    minLines: 12,
                    maxLines: 24,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Content (markdown)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : (_isEditing ? 'Save changes' : 'Create report')),
                  ),
                ],
              ),
      ),
    );
  }
}
