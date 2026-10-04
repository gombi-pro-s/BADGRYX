import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_ctf.dart';

/// Mirrors `admin/ctf/page.tsx` + `[challengeId]/page.tsx` + `actions.ts`
/// -- plain RLS-scoped Postgrest CRUD on `ctf_challenges`
/// (`FOR ALL ... USING (is_staff())`), with the one flag hashed on-device
/// before it ever reaches Postgrest (see `admin_ctf.dart`'s `hashCtfFlag`).
/// No delete action, same reasoning as `admin_ctf_events_screen.dart`.
Future<List<AdminCtfChallenge>> fetchAdminCtfChallenges(SupabaseClient client) async {
  final rows = await client
      .from('ctf_challenges')
      .select('id, slug, title, description, category, difficulty, points, published, event_id')
      .order('title');
  return (rows as List).map((row) => AdminCtfChallenge.fromRow(row as Map<String, dynamic>)).toList();
}

Future<List<Map<String, String>>> _fetchEventOptions(SupabaseClient client) async {
  final rows = await client.from('ctf_events').select('id, title').order('title');
  return (rows as List)
      .map((row) => {'id': row['id'] as String, 'title': row['title'] as String})
      .toList();
}

class AdminCtfChallengesScreen extends StatefulWidget {
  const AdminCtfChallengesScreen({super.key});

  @override
  State<AdminCtfChallengesScreen> createState() => _AdminCtfChallengesScreenState();
}

class _AdminCtfChallengesScreenState extends State<AdminCtfChallengesScreen> {
  late Future<List<AdminCtfChallenge>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminCtfChallenges(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminCtfChallenges(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openForm({String? challengeId}) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AdminCtfChallengeFormScreen(challengeId: challengeId)));
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CTF Challenges')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'New challenge',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminCtfChallenge>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load challenges: ${snapshot.error}'));
            }
            final challenges = snapshot.data ?? [];
            if (challenges.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No challenges yet. Create the first one with the + button.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: challenges.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final challenge = challenges[index];
                return Card(
                  child: ListTile(
                    title: Text(challenge.title),
                    subtitle: Text('${challenge.category} · ${challenge.difficulty} · ${challenge.points} pts'),
                    trailing: Chip(label: Text(challenge.published ? 'Published' : 'Draft')),
                    onTap: () => _openForm(challengeId: challenge.id),
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

/// Create when `challengeId` is null, edit otherwise. Skill tagging only
/// appears once editing -- same constraint as the web page, which can only
/// tag skills on a challenge that already has an id.
class AdminCtfChallengeFormScreen extends StatefulWidget {
  const AdminCtfChallengeFormScreen({super.key, this.challengeId});

  final String? challengeId;

  @override
  State<AdminCtfChallengeFormScreen> createState() => _AdminCtfChallengeFormScreenState();
}

class _AdminCtfChallengeFormScreenState extends State<AdminCtfChallengeFormScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pointsController = TextEditingController(text: '100');
  final _plaintextController = TextEditingController();
  String _category = 'web';
  String _difficulty = 'easy';
  String? _eventId;
  bool _published = false;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;
  List<Map<String, String>> _events = const [];
  List<Map<String, dynamic>> _allSkills = const [];
  Set<String> _selectedSkillIds = {};
  bool _skillsSaving = false;
  bool _skillsSaved = false;

  bool get _isEditing => widget.challengeId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final events = await _fetchEventOptions(client);
      if (_isEditing) {
        final row = await client
            .from('ctf_challenges')
            .select('id, slug, title, description, category, difficulty, points, published, event_id')
            .eq('id', widget.challengeId!)
            .single();
        final challenge = AdminCtfChallenge.fromRow(row);
        final allSkillsRows = await client.from('skills').select('id, name').order('name');
        final challengeSkillRows = await client
            .from('ctf_challenge_skills')
            .select('skill_id')
            .eq('challenge_id', widget.challengeId!);
        _titleController.text = challenge.title;
        _slugController.text = challenge.slug;
        _descriptionController.text = challenge.description ?? '';
        _pointsController.text = challenge.points.toString();
        setState(() {
          _category = challenge.category;
          _difficulty = challenge.difficulty;
          _eventId = challenge.eventId;
          _published = challenge.published;
          _events = events;
          _allSkills = (allSkillsRows as List).cast<Map<String, dynamic>>();
          _selectedSkillIds = (challengeSkillRows as List).map((r) => r['skill_id'] as String).toSet();
          _loading = false;
        });
      } else {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load this challenge.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final plaintext = _plaintextController.text.trim();
    final points = int.tryParse(_pointsController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidCtfSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (points == null || points < 0 || points > 10000) {
      setState(() => _error = 'Points must be between 0 and 10000.');
      return;
    }
    if (!_isEditing && plaintext.length < 4) {
      setState(() => _error = 'Flag must be at least 4 characters.');
      return;
    }
    if (_isEditing && plaintext.isNotEmpty && plaintext.length < 4) {
      setState(() => _error = 'New flag must be at least 4 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    final payload = <String, dynamic>{
      'slug': slug,
      'title': title,
      'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'category': _category,
      'difficulty': _difficulty,
      'points': points,
      'event_id': _eventId,
    };
    if (!_isEditing || plaintext.isNotEmpty) {
      payload['flag_hash'] = hashCtfFlag(plaintext);
    }
    try {
      if (_isEditing) {
        await client.from('ctf_challenges').update(payload).eq('id', widget.challengeId!);
      } else {
        await client.from('ctf_challenges').insert(payload);
      }
      _changed = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug is already in use.'
          : (_isEditing ? 'Could not save changes.' : 'Could not create the challenge.');
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client.from('ctf_challenges').update({'published': value}).eq('id', widget.challengeId!);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'ctf_challenge.published' : 'ctf_challenge.unpublished',
          'p_target_type': 'ctf_challenge',
          'p_target_id': widget.challengeId,
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

  Future<void> _saveSkills() async {
    setState(() {
      _skillsSaving = true;
      _skillsSaved = false;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('ctf_challenge_skills').delete().eq('challenge_id', widget.challengeId!);
      if (_selectedSkillIds.isNotEmpty) {
        await client
            .from('ctf_challenge_skills')
            .insert(_selectedSkillIds.map((skillId) => {'challenge_id': widget.challengeId, 'skill_id': skillId}).toList());
      }
      _changed = true;
      setState(() {
        _skillsSaving = false;
        _skillsSaved = true;
      });
    } catch (e) {
      setState(() {
        _skillsSaving = false;
        _error = 'Could not save skills.';
      });
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
        appBar: AppBar(title: Text(_isEditing ? 'Edit challenge' : 'New challenge')),
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
                    decoration: const InputDecoration(labelText: 'Slug', hintText: 'web-sqli-1'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _eventId,
                    decoration: const InputDecoration(labelText: 'CTF event (optional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None -- independent challenge')),
                      ..._events.map((e) => DropdownMenuItem(value: e['id'], child: Text(e['title']!))),
                    ],
                    onChanged: (value) => setState(() => _eventId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: ctfCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (value) => setState(() => _category = value ?? 'web'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _difficulty,
                    decoration: const InputDecoration(labelText: 'Difficulty'),
                    items: ctfDifficulties.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (value) => setState(() => _difficulty = value ?? 'easy'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Points'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _plaintextController,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: _isEditing ? 'New flag (leave blank to keep the current one)' : 'Flag',
                      helperText: 'Hashed (SHA-256) the moment you submit. Never stored or shown as plaintext again.',
                    ),
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 20),
                    Text('Skills demonstrated', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allSkills.map((skill) {
                        final id = skill['id'] as String;
                        final selected = _selectedSkillIds.contains(id);
                        return FilterChip(
                          label: Text(skill['name'] as String),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              _skillsSaved = false;
                              if (value) {
                                _selectedSkillIds.add(id);
                              } else {
                                _selectedSkillIds.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _skillsSaving ? null : _saveSkills,
                          child: Text(_skillsSaving ? 'Saving...' : 'Save skills'),
                        ),
                        if (_skillsSaved && !_skillsSaving) ...[
                          const SizedBox(width: 12),
                          const Text('Saved.'),
                        ],
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : (_isEditing ? 'Save changes' : 'Create challenge')),
                  ),
                ],
              ),
      ),
    );
  }
}
