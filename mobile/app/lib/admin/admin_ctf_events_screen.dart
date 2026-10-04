import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_ctf.dart';

/// Mirrors `admin/ctf-events/page.tsx` + `[eventId]/page.tsx` + `actions.ts`
/// -- plain RLS-scoped Postgrest CRUD on `ctf_events`, which is
/// `FOR ALL ... USING (is_staff())` the same way `ctf_challenges` is (see
/// `20260921000009_content_model_rls.sql` and
/// `20260922000028_blue_purple_scenario_linkage.sql`), so there's no Route
/// Handler to build here, same reasoning as every other admin CMS screen
/// ported to mobile so far. No delete action here because the web admin UI
/// doesn't have one either -- an event may already have challenges and
/// submissions tied to it.
Future<List<AdminCtfEvent>> fetchAdminCtfEvents(SupabaseClient client) async {
  final rows = await client
      .from('ctf_events')
      .select('id, slug, title, description, scoring_type, starts_at, ends_at, published')
      .order('created_at', ascending: false);
  return (rows as List).map((row) => AdminCtfEvent.fromRow(row as Map<String, dynamic>)).toList();
}

class AdminCtfEventsScreen extends StatefulWidget {
  const AdminCtfEventsScreen({super.key});

  @override
  State<AdminCtfEventsScreen> createState() => _AdminCtfEventsScreenState();
}

class _AdminCtfEventsScreenState extends State<AdminCtfEventsScreen> {
  late Future<List<AdminCtfEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminCtfEvents(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminCtfEvents(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openForm({String? eventId}) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AdminCtfEventFormScreen(eventId: eventId)));
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CTF Events')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'New event',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminCtfEvent>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load events: ${snapshot.error}'));
            }
            final events = snapshot.data ?? [];
            if (events.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No CTF events yet. Create the first one with the + button. A challenge with no '
                      'event stays an independent challenge.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  child: ListTile(
                    title: Text(event.title),
                    subtitle: Text('/${event.slug}'),
                    trailing: Chip(label: Text(event.published ? 'Published' : 'Draft')),
                    onTap: () => _openForm(eventId: event.id),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Create when `eventId` is null, edit otherwise -- same reasoning as every
/// other combined create/edit screen in this app for why one screen
/// replaces the web's two pages.
class AdminCtfEventFormScreen extends StatefulWidget {
  const AdminCtfEventFormScreen({super.key, this.eventId});

  final String? eventId;

  @override
  State<AdminCtfEventFormScreen> createState() => _AdminCtfEventFormScreenState();
}

class _AdminCtfEventFormScreenState extends State<AdminCtfEventFormScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _scoringType = 'static';
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _published = false;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;
  List<AdminCtfChallenge> _challenges = const [];

  bool get _isEditing => widget.eventId != null;

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
      final client = Supabase.instance.client;
      final row = await client
          .from('ctf_events')
          .select('id, slug, title, description, scoring_type, starts_at, ends_at, published')
          .eq('id', widget.eventId!)
          .single();
      final event = AdminCtfEvent.fromRow(row);
      final challengeRows = await client
          .from('ctf_challenges')
          .select('id, slug, title, description, category, difficulty, points, published, event_id')
          .eq('event_id', widget.eventId!)
          .order('title');
      _titleController.text = event.title;
      _slugController.text = event.slug;
      _descriptionController.text = event.description ?? '';
      setState(() {
        _scoringType = event.scoringType;
        _startsAt = event.startsAt;
        _endsAt = event.endsAt;
        _published = event.published;
        _challenges = (challengeRows as List)
            .map((row) => AdminCtfChallenge.fromRow(row as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this event.';
        _loading = false;
      });
    }
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidCtfSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    final rangeError = ctfEventTimeRangeError(_startsAt, _endsAt);
    if (rangeError != null) {
      setState(() => _error = rangeError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final payload = {
      'slug': slug,
      'title': title,
      'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'scoring_type': _scoringType,
      'starts_at': _startsAt?.toUtc().toIso8601String(),
      'ends_at': _endsAt?.toUtc().toIso8601String(),
    };
    try {
      if (_isEditing) {
        await client.from('ctf_events').update(payload).eq('id', widget.eventId!);
      } else {
        await client.from('ctf_events').insert(payload);
      }
      _changed = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug is already in use.'
          : (_isEditing ? 'Could not save changes.' : 'Could not create the event.');
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client.from('ctf_events').update({'published': value}).eq('id', widget.eventId!);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'ctf_event.published' : 'ctf_event.unpublished',
          'p_target_type': 'ctf_event',
          'p_target_id': widget.eventId,
        },
      );
      setState(() {
        _published = value;
        _changed = true;
      });
    } catch (e) {
      setState(() => _error = 'Could not change the published state.');
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
        appBar: AppBar(title: Text(_isEditing ? 'Edit event' : 'New event')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isEditing) ...[
                    SwitchListTile(
                      title: const Text('Published'),
                      value: _published,
                      onChanged: _togglePublished,
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _slugController,
                    decoration: const InputDecoration(labelText: 'Slug', hintText: 'spring-ctf'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _scoringType,
                    decoration: const InputDecoration(labelText: 'Scoring'),
                    items: ctfScoringTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t == 'static' ? 'Static' : 'Dynamic')))
                        .toList(),
                    onChanged: (value) => setState(() => _scoringType = value ?? 'static'),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Dynamic scoring (points decaying as more competitors solve a challenge) is not '
                      'implemented yet -- picking it stores the intent but challenges still score at their '
                      'fixed points.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_startsAt == null ? 'No start time' : 'Starts ${_startsAt!.toLocal()}'.split('.').first),
                      ),
                      TextButton(onPressed: () => _pickDateTime(isStart: true), child: const Text('Set')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_endsAt == null ? 'No end time' : 'Ends ${_endsAt!.toLocal()}'.split('.').first),
                      ),
                      TextButton(onPressed: () => _pickDateTime(isStart: false), child: const Text('Set')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Challenges in this event (${_challenges.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (_challenges.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No challenges assigned yet. Set this event from a challenge\'s own edit form.'),
                      )
                    else
                      ..._challenges.map(
                        (c) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.title),
                          trailing: Text(c.published ? 'Published' : 'Draft'),
                        ),
                      ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : (_isEditing ? 'Save changes' : 'Create event')),
                  ),
                ],
              ),
      ),
    );
  }
}
