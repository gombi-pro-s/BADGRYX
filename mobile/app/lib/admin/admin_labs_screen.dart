import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'admin_ctf.dart' show ctfCategories, ctfDifficulties, hashCtfFlag;
import 'admin_lab.dart';

/// Mirrors `admin/labs/page.tsx` + `[labId]/page.tsx` + `hints-manager.tsx`
/// + `flags-manager.tsx` + `actions.ts` -- plain RLS-scoped Postgrest CRUD
/// on `labs`/`lab_skills`/`lab_hints`/`lab_flags` (all staff-write -- see
/// `20260921000009_content_model_rls.sql`), no Route Handler. Category/
/// difficulty are `LabCategory`/`DifficultyLevel`, the exact same enums
/// CTF Challenges uses, so this screen reuses `ctfCategories`/
/// `ctfDifficulties` rather than redeclaring identical lists; flags are
/// hashed with the same `hashCtfFlag()` (lowercase hex SHA-256) for the
/// same reason ADR 0053 hashes CTF flags on-device.
///
/// `environment-manager.tsx` (the terminal environment's spec JSON
/// editor) ported in ADR 0057: listing/loading/removing an environment
/// stays plain Postgrest (`lab_environments_staff_only` is `FOR ALL`, so
/// read needs no more authorization than write does), but *saving* goes
/// through the new Bearer-authed `/api/admin/labs/{labId}/environments`
/// Route Handler, which validates the submitted JSON against
/// `lib/terminal/spec.ts`'s `environmentSpecSchema` -- the same schema
/// `lib/terminal/execute.ts` parses it with -- before the upsert, since
/// the database itself only checks `spec` is a JSON object
/// (`lab_environments_spec_is_object`), nothing about its shape. Shown
/// only when `AppEnv.isApiConfigured`, same as every other screen that
/// calls a Route Handler directly. See ADR 0056/0057.
Future<List<AdminLab>> fetchAdminLabs(SupabaseClient client) async {
  final rows = await client
      .from('labs')
      .select('id, slug, title, description, category, difficulty, estimated_minutes, points, published')
      .order('title');
  return (rows as List).map((row) => AdminLab.fromRow(row as Map<String, dynamic>)).toList();
}

class AdminLabsScreen extends StatefulWidget {
  const AdminLabsScreen({super.key});

  @override
  State<AdminLabsScreen> createState() => _AdminLabsScreenState();
}

class _AdminLabsScreenState extends State<AdminLabsScreen> {
  late Future<List<AdminLab>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminLabs(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminLabs(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AdminCreateLabScreen()));
    if (created == true) await _refresh();
  }

  Future<void> _openDetail(String labId) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AdminLabDetailScreen(labId: labId)));
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Labs')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        tooltip: 'New lab',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminLab>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load labs: ${snapshot.error}'));
            }
            final labs = snapshot.data ?? [];
            if (labs.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No labs yet. Create the first one with the + button.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: labs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final lab = labs[index];
                return Card(
                  child: ListTile(
                    title: Text(lab.title),
                    subtitle: Text('${lab.category} · ${lab.difficulty}'),
                    trailing: Chip(label: Text(lab.published ? 'Published' : 'Draft')),
                    onTap: () => _openDetail(lab.id),
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

class AdminCreateLabScreen extends StatefulWidget {
  const AdminCreateLabScreen({super.key});

  @override
  State<AdminCreateLabScreen> createState() => _AdminCreateLabScreenState();
}

class _AdminCreateLabScreenState extends State<AdminCreateLabScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _minutesController = TextEditingController(text: '60');
  final _pointsController = TextEditingController(text: '100');
  String _category = 'web';
  String _difficulty = 'easy';
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    final points = int.tryParse(_pointsController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidLabSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _error = 'Estimated minutes must be between 1 and 600.');
      return;
    }
    if (points == null || points < 0 || points > 10000) {
      setState(() => _error = 'Points must be between 0 and 10000.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.from('labs').insert({
        'slug': slug,
        'title': title,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'category': _category,
        'difficulty': _difficulty,
        'estimated_minutes': minutes,
        'points': points,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug is already in use.'
          : 'Could not create the lab.';
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New lab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _titleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(
            controller: _slugController,
            decoration: const InputDecoration(labelText: 'Slug', hintText: 'sqli-101'),
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
            controller: _minutesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Estimated minutes'),
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
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Creating...' : 'Create lab')),
        ],
      ),
    );
  }
}

class AdminLabDetailScreen extends StatefulWidget {
  const AdminLabDetailScreen({super.key, required this.labId});

  final String labId;

  @override
  State<AdminLabDetailScreen> createState() => _AdminLabDetailScreenState();
}

class _AdminLabDetailScreenState extends State<AdminLabDetailScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _minutesController = TextEditingController();
  final _pointsController = TextEditingController();
  String _category = 'web';
  String _difficulty = 'easy';

  final _hintLevelController = TextEditingController();
  final _hintCostController = TextEditingController(text: '0');
  final _hintContentController = TextEditingController();

  final _flagLabelController = TextEditingController(text: 'flag');
  final _flagVariantController = TextEditingController(text: '0');
  final _flagPlaintextController = TextEditingController();

  bool _loading = true;
  bool _changed = false;
  bool _published = false;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _allSkills = const [];
  Set<String> _selectedSkillIds = {};
  bool _skillsSaving = false;
  bool _skillsSaved = false;
  List<AdminLabHint> _hints = const [];
  bool _addingHint = false;
  String? _hintError;
  List<AdminLabFlag> _flags = const [];
  bool _addingFlag = false;
  String? _flagError;

  final _envVariantSeedController = TextEditingController(text: '0');
  final _envSpecController = TextEditingController(text: placeholderEnvironmentSpecJson);
  List<AdminLabEnvironment> _environments = const [];
  bool _savingEnvironment = false;
  String? _environmentError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final labRow = await client
          .from('labs')
          .select('id, slug, title, description, category, difficulty, estimated_minutes, points, published')
          .eq('id', widget.labId)
          .single();
      final lab = AdminLab.fromRow(labRow);
      final allSkillsRows = await client.from('skills').select('id, name').order('name');
      final labSkillRows = await client.from('lab_skills').select('skill_id').eq('lab_id', widget.labId);
      final hintRows = await client.from('lab_hints').select('id, level, content, point_cost').eq('lab_id', widget.labId);
      final flagRows = await client.from('lab_flags').select('id, label, variant_seed').eq('lab_id', widget.labId);
      final environmentRows = await client
          .from('lab_environments')
          .select('id, variant_seed, spec')
          .eq('lab_id', widget.labId)
          .order('variant_seed');
      _titleController.text = lab.title;
      _slugController.text = lab.slug;
      _descriptionController.text = lab.description ?? '';
      _minutesController.text = lab.estimatedMinutes.toString();
      _pointsController.text = lab.points.toString();
      final hints = (hintRows as List).map((row) => AdminLabHint.fromRow(row as Map<String, dynamic>)).toList()
        ..sort((a, b) => a.level.compareTo(b.level));
      setState(() {
        _category = lab.category;
        _difficulty = lab.difficulty;
        _published = lab.published;
        _allSkills = (allSkillsRows as List).cast<Map<String, dynamic>>();
        _selectedSkillIds = (labSkillRows as List).map((r) => r['skill_id'] as String).toSet();
        _hints = hints;
        _flags = (flagRows as List).map((row) => AdminLabFlag.fromRow(row as Map<String, dynamic>)).toList();
        _environments = (environmentRows as List)
            .map((row) => AdminLabEnvironment.fromRow(row as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this lab.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    final points = int.tryParse(_pointsController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidLabSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _error = 'Estimated minutes must be between 1 and 600.');
      return;
    }
    if (points == null || points < 0 || points > 10000) {
      setState(() => _error = 'Points must be between 0 and 10000.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('labs')
          .update({
            'slug': slug,
            'title': title,
            'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
            'category': _category,
            'difficulty': _difficulty,
            'estimated_minutes': minutes,
            'points': points,
          })
          .eq('id', widget.labId);
      _changed = true;
      setState(() => _saving = false);
    } catch (e) {
      setState(() {
        _error = 'Could not save changes.';
        _saving = false;
      });
    }
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client.from('labs').update({'published': value}).eq('id', widget.labId);
      await client.rpc(
        'log_audit_event',
        params: {'p_action': value ? 'lab.published' : 'lab.unpublished', 'p_target_type': 'lab', 'p_target_id': widget.labId},
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
      await client.from('lab_skills').delete().eq('lab_id', widget.labId);
      if (_selectedSkillIds.isNotEmpty) {
        await client
            .from('lab_skills')
            .insert(_selectedSkillIds.map((skillId) => {'lab_id': widget.labId, 'skill_id': skillId}).toList());
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

  Future<void> _addHint() async {
    final level = int.tryParse(_hintLevelController.text.trim());
    final cost = int.tryParse(_hintCostController.text.trim());
    final content = _hintContentController.text.trim();
    if (level == null || level < 1 || level > 5) {
      setState(() => _hintError = 'Level must be between 1 and 5.');
      return;
    }
    if (cost == null || cost < 0 || cost > 1000) {
      setState(() => _hintError = 'Point cost must be between 0 and 1000.');
      return;
    }
    if (content.isEmpty) {
      setState(() => _hintError = 'Hint text is required.');
      return;
    }
    setState(() {
      _addingHint = true;
      _hintError = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('lab_hints').insert({'lab_id': widget.labId, 'level': level, 'content': content, 'point_cost': cost});
      _hintLevelController.clear();
      _hintCostController.text = '0';
      _hintContentController.clear();
      _changed = true;
      await _reloadHints(client);
      setState(() => _addingHint = false);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'A hint already exists at that level.'
          : 'Could not add this hint.';
      setState(() {
        _hintError = message;
        _addingHint = false;
      });
    }
  }

  Future<void> _reloadHints(SupabaseClient client) async {
    final hintRows = await client.from('lab_hints').select('id, level, content, point_cost').eq('lab_id', widget.labId);
    final hints = (hintRows as List).map((row) => AdminLabHint.fromRow(row as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.level.compareTo(b.level));
    setState(() => _hints = hints);
  }

  Future<void> _removeHint(String hintId) async {
    final client = Supabase.instance.client;
    try {
      await client.from('lab_hints').delete().eq('id', hintId);
      _changed = true;
      await _reloadHints(client);
    } catch (e) {
      setState(() => _error = 'Could not remove this hint.');
    }
  }

  Future<void> _addFlag() async {
    final label = _flagLabelController.text.trim();
    final variantSeed = int.tryParse(_flagVariantController.text.trim());
    final plaintext = _flagPlaintextController.text.trim();
    if (label.isEmpty) {
      setState(() => _flagError = 'Label is required.');
      return;
    }
    if (variantSeed == null || variantSeed < 0 || variantSeed > 9999) {
      setState(() => _flagError = 'Variant seed must be between 0 and 9999.');
      return;
    }
    if (plaintext.length < 4) {
      setState(() => _flagError = 'Flag must be at least 4 characters.');
      return;
    }
    setState(() {
      _addingFlag = true;
      _flagError = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('lab_flags').insert({
        'lab_id': widget.labId,
        'label': label,
        'flag_hash': hashCtfFlag(plaintext),
        'variant_seed': variantSeed,
      });
      _flagLabelController.text = 'flag';
      _flagVariantController.text = '0';
      _flagPlaintextController.clear();
      _changed = true;
      await _reloadFlags(client);
      setState(() => _addingFlag = false);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'A flag with that label/variant already exists.'
          : 'Could not add this flag.';
      setState(() {
        _flagError = message;
        _addingFlag = false;
      });
    }
  }

  Future<void> _reloadFlags(SupabaseClient client) async {
    final flagRows = await client.from('lab_flags').select('id, label, variant_seed').eq('lab_id', widget.labId);
    setState(() => _flags = (flagRows as List).map((row) => AdminLabFlag.fromRow(row as Map<String, dynamic>)).toList());
  }

  Future<void> _removeFlag(String flagId) async {
    final client = Supabase.instance.client;
    try {
      await client.from('lab_flags').delete().eq('id', flagId);
      _changed = true;
      await _reloadFlags(client);
    } catch (e) {
      setState(() => _error = 'Could not remove this flag.');
    }
  }

  Future<void> _reloadEnvironments(SupabaseClient client) async {
    final rows = await client
        .from('lab_environments')
        .select('id, variant_seed, spec')
        .eq('lab_id', widget.labId)
        .order('variant_seed');
    setState(() {
      _environments = (rows as List).map((row) => AdminLabEnvironment.fromRow(row as Map<String, dynamic>)).toList();
    });
  }

  void _loadEnvironmentIntoEditor(AdminLabEnvironment environment) {
    setState(() => _envSpecController.text = prettyPrintJson(environment.spec));
  }

  /// POSTs to the new `/api/admin/labs/{labId}/environments` Route
  /// Handler (ADR 0057) rather than a plain Postgrest upsert -- it's the
  /// only write in this whole screen that needs server-side validation
  /// beyond RLS (see the class doc comment for why).
  Future<void> _saveEnvironment() async {
    final variantSeed = int.tryParse(_envVariantSeedController.text.trim());
    final specJson = _envSpecController.text.trim();
    if (variantSeed == null || variantSeed < 0 || variantSeed > 9999) {
      setState(() => _environmentError = 'Variant seed must be between 0 and 9999.');
      return;
    }
    if (specJson.isEmpty) {
      setState(() => _environmentError = 'Spec JSON is required.');
      return;
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _environmentError = 'Your session has expired. Please log in again.');
      return;
    }
    setState(() {
      _savingEnvironment = true;
      _environmentError = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${AppEnv.apiBaseUrl}/api/admin/labs/${widget.labId}/environments'),
        headers: {'Authorization': 'Bearer ${session.accessToken}', 'Content-Type': 'application/json'},
        body: jsonEncode({'variant_seed': variantSeed, 'spec_json': specJson}),
      );
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['error'] as String? ?? 'Save failed (${response.statusCode}).');
      }
      _changed = true;
      await _reloadEnvironments(Supabase.instance.client);
      setState(() => _savingEnvironment = false);
    } catch (e) {
      setState(() {
        _environmentError = e.toString().replaceFirst('Exception: ', '');
        _savingEnvironment = false;
      });
    }
  }

  Future<void> _removeEnvironment(String environmentId) async {
    final client = Supabase.instance.client;
    try {
      await client.from('lab_environments').delete().eq('id', environmentId);
      _changed = true;
      await _reloadEnvironments(client);
    } catch (e) {
      setState(() => _error = 'Could not remove this environment.');
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
        appBar: AppBar(title: const Text('Lab details')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(title: const Text('Published'), value: _published, onChanged: _togglePublished),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _slugController, decoration: const InputDecoration(labelText: 'Slug')),
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
                    controller: _minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Estimated minutes'),
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
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save changes')),
                  const SizedBox(height: 24),
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
                      if (_skillsSaved && !_skillsSaving) ...[const SizedBox(width: 12), const Text('Saved.')],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Hints', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_hints.isEmpty)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No hints yet.'))
                  else
                    ..._hints.map(
                      (hint) => Card(
                        child: ListTile(
                          title: Text(hint.content),
                          subtitle: Text('Level ${hint.level} · ${hint.pointCost} pts'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeHint(hint.id),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _hintLevelController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Level (1-5)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _hintCostController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Point cost'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _hintContentController,
                          maxLines: 2,
                          maxLength: 2000,
                          decoration: const InputDecoration(labelText: 'Hint text'),
                        ),
                        if (_hintError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_hintError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _addingHint ? null : _addHint,
                          child: Text(_addingHint ? 'Adding...' : 'Add hint'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Flags', style: Theme.of(context).textTheme.titleSmall),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Hashed (SHA-256) the moment you submit. The plaintext is never stored, logged, or '
                      'shown again after creation -- write it down before submitting.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_flags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('No flags yet. The lab cannot be completed without one.'),
                    )
                  else
                    ..._flags.map(
                      (flag) => Card(
                        child: ListTile(
                          title: Text(flag.label),
                          subtitle: Text('Variant ${flag.variantSeed}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeFlag(flag.id),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _flagLabelController,
                                maxLength: 100,
                                decoration: const InputDecoration(labelText: 'Label'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _flagVariantController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Variant seed'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _flagPlaintextController,
                          maxLength: 500,
                          decoration: const InputDecoration(labelText: 'Flag (plaintext, hashed on submit)'),
                        ),
                        if (_flagError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_flagError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _addingFlag ? null : _addFlag,
                          child: Text(_addingFlag ? 'Adding...' : 'Add flag'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Terminal environment', style: Theme.of(context).textTheme.titleSmall),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      "The spec is never sent to a learner's browser directly -- only the output of a "
                      'command they run against it. Saving here validates against the exact schema the '
                      'terminal execution engine parses, so a spec that saves is one that will actually work.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (!AppEnv.isApiConfigured)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Not configured on this build (needs API_BASE_URL) -- environments can still be '
                        'viewed and removed below, just not saved from this app.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (_environments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No terminal environment yet -- this lab has no interactive terminal until one is saved.',
                      ),
                    )
                  else
                    ..._environments.map(
                      (env) => Card(
                        child: ListTile(
                          title: Text('Variant ${env.variantSeed}'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: () => _loadEnvironmentIntoEditor(env),
                                child: const Text('Load into editor'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeEnvironment(env.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (AppEnv.isApiConfigured)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _envVariantSeedController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Variant seed'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _envSpecController,
                            maxLines: 14,
                            decoration: const InputDecoration(labelText: 'Environment spec (JSON)', alignLabelWithHint: true),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                          if (_environmentError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _environmentError!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: _savingEnvironment ? null : _saveEnvironment,
                            child: Text(_savingEnvironment ? 'Saving...' : 'Save environment'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
