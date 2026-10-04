import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_path.dart';

/// Mirrors `admin/paths/page.tsx` + `[pathId]/page.tsx` +
/// `[pathId]/[moduleId]/page.tsx` + `[pathId]/[moduleId]/[lessonId]/page.tsx`
/// + `actions.ts` -- plain RLS-scoped Postgrest CRUD at all three levels
/// (`learning_paths`/`modules`/`lessons`/`lesson_skills` are all
/// staff-write, anyone-reads-published -- see
/// `20260921000009_content_model_rls.sql`), no Route Handler needed, same
/// shape as every other admin CMS screen on mobile. `order_index` is left
/// at its DB default (0) on every insert here, same as the web admin UI,
/// which has no reordering control either. Path import/export (the JSON
/// bundle flow at `/admin/paths/import` and `/admin/paths/[pathId]/export`)
/// is a separate, still-unbuilt gap -- not attempted here. See ADR 0055.
Future<List<AdminLearningPath>> fetchAdminPaths(SupabaseClient client) async {
  final rows = await client
      .from('learning_paths')
      .select('id, slug, title, description, published')
      .order('order_index');
  return (rows as List).map((row) => AdminLearningPath.fromRow(row as Map<String, dynamic>)).toList();
}

class AdminPathsScreen extends StatefulWidget {
  const AdminPathsScreen({super.key});

  @override
  State<AdminPathsScreen> createState() => _AdminPathsScreenState();
}

class _AdminPathsScreenState extends State<AdminPathsScreen> {
  late Future<List<AdminLearningPath>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminPaths(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminPaths(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AdminCreatePathScreen()));
    if (created == true) await _refresh();
  }

  Future<void> _openDetail(String pathId) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => AdminPathDetailScreen(pathId: pathId)));
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning Paths')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        tooltip: 'New path',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AdminLearningPath>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load learning paths: ${snapshot.error}'));
            }
            final paths = snapshot.data ?? [];
            if (paths.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No learning paths yet. Create the first one with the + button.'),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: paths.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final path = paths[index];
                return Card(
                  child: ListTile(
                    title: Text(path.title),
                    subtitle: Text('/${path.slug}'),
                    trailing: Chip(label: Text(path.published ? 'Published' : 'Draft')),
                    onTap: () => _openDetail(path.id),
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

class AdminCreatePathScreen extends StatefulWidget {
  const AdminCreatePathScreen({super.key});

  @override
  State<AdminCreatePathScreen> createState() => _AdminCreatePathScreenState();
}

class _AdminCreatePathScreenState extends State<AdminCreatePathScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidContentSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('learning_paths').insert({
        'slug': slug,
        'title': title,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'created_by': client.auth.currentUser!.id,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug is already in use.'
          : 'Could not create the path.';
      setState(() {
        _error = message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New learning path')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _titleController, maxLength: 200, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(
            controller: _slugController,
            decoration: const InputDecoration(labelText: 'Slug', hintText: 'web-app-security'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Creating...' : 'Create path')),
        ],
      ),
    );
  }
}

class AdminPathDetailScreen extends StatefulWidget {
  const AdminPathDetailScreen({super.key, required this.pathId});

  final String pathId;

  @override
  State<AdminPathDetailScreen> createState() => _AdminPathDetailScreenState();
}

class _AdminPathDetailScreenState extends State<AdminPathDetailScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _moduleTitleController = TextEditingController();
  final _moduleSlugController = TextEditingController();
  final _moduleDescriptionController = TextEditingController();

  bool _loading = true;
  bool _changed = false;
  bool _published = false;
  bool _saving = false;
  bool _creatingModule = false;
  String? _error;
  String? _moduleError;
  List<AdminModuleSummary> _modules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final pathRow = await client
          .from('learning_paths')
          .select('id, slug, title, description, published')
          .eq('id', widget.pathId)
          .single();
      final path = AdminLearningPath.fromRow(pathRow);
      final moduleRows = await client
          .from('modules')
          .select('id, title, published, order_index')
          .eq('path_id', widget.pathId)
          .order('order_index');
      _titleController.text = path.title;
      _slugController.text = path.slug;
      _descriptionController.text = path.description ?? '';
      setState(() {
        _published = path.published;
        _modules = (moduleRows as List).map((row) => AdminModuleSummary.fromRow(row as Map<String, dynamic>)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this path.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidContentSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('learning_paths')
          .update({
            'slug': slug,
            'title': title,
            'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
          })
          .eq('id', widget.pathId);
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
      await client.from('learning_paths').update({'published': value}).eq('id', widget.pathId);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'learning_path.published' : 'learning_path.unpublished',
          'p_target_type': 'learning_path',
          'p_target_id': widget.pathId,
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

  Future<void> _createModule() async {
    final title = _moduleTitleController.text.trim();
    final slug = _moduleSlugController.text.trim();
    if (title.isEmpty) {
      setState(() => _moduleError = 'Title is required.');
      return;
    }
    if (!isValidContentSlug(slug)) {
      setState(() => _moduleError = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    setState(() {
      _creatingModule = true;
      _moduleError = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('modules').insert({
        'path_id': widget.pathId,
        'slug': slug,
        'title': title,
        'description': _moduleDescriptionController.text.trim().isEmpty ? null : _moduleDescriptionController.text.trim(),
      });
      _moduleTitleController.clear();
      _moduleSlugController.clear();
      _moduleDescriptionController.clear();
      _changed = true;
      final moduleRows = await client
          .from('modules')
          .select('id, title, published, order_index')
          .eq('path_id', widget.pathId)
          .order('order_index');
      setState(() {
        _modules = (moduleRows as List).map((row) => AdminModuleSummary.fromRow(row as Map<String, dynamic>)).toList();
        _creatingModule = false;
      });
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug already exists in this path.'
          : 'Could not create the module.';
      setState(() {
        _moduleError = message;
        _creatingModule = false;
      });
    }
  }

  Future<void> _openModule(String moduleId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminModuleDetailScreen(pathId: widget.pathId, moduleId: moduleId)),
    );
    if (changed == true) {
      _changed = true;
      await _load();
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
        appBar: AppBar(title: const Text('Path details')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text('Published'),
                    value: _published,
                    onChanged: _togglePublished,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _slugController, decoration: const InputDecoration(labelText: 'Slug')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save changes')),
                  const SizedBox(height: 24),
                  Text('Modules', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_modules.isEmpty)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No modules yet.'))
                  else
                    ..._modules.map(
                      (m) => Card(
                        child: ListTile(
                          title: Text(m.title),
                          trailing: Chip(label: Text(m.published ? 'Published' : 'Draft')),
                          onTap: () => _openModule(m.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New module'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _moduleTitleController,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _moduleSlugController,
                          decoration: const InputDecoration(labelText: 'Slug', hintText: 'sql-injection'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _moduleDescriptionController,
                          maxLines: 2,
                          maxLength: 2000,
                          decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                        ),
                        if (_moduleError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_moduleError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _creatingModule ? null : _createModule,
                          child: Text(_creatingModule ? 'Creating...' : 'Create module'),
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

class AdminModuleDetailScreen extends StatefulWidget {
  const AdminModuleDetailScreen({super.key, required this.pathId, required this.moduleId});

  final String pathId;
  final String moduleId;

  @override
  State<AdminModuleDetailScreen> createState() => _AdminModuleDetailScreenState();
}

class _AdminModuleDetailScreenState extends State<AdminModuleDetailScreen> {
  final _lessonTitleController = TextEditingController();
  final _lessonSlugController = TextEditingController();
  final _lessonSummaryController = TextEditingController();
  final _lessonContentController = TextEditingController();
  final _lessonMinutesController = TextEditingController(text: '10');

  bool _loading = true;
  bool _changed = false;
  bool _published = false;
  String _title = '';
  String? _error;
  String? _lessonError;
  bool _creatingLesson = false;
  List<AdminLessonSummary> _lessons = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final moduleRow = await client.from('modules').select('id, title, published').eq('id', widget.moduleId).single();
      final lessonRows = await client
          .from('lessons')
          .select('id, title, published, order_index')
          .eq('module_id', widget.moduleId)
          .order('order_index');
      setState(() {
        _title = moduleRow['title'] as String;
        _published = moduleRow['published'] as bool;
        _lessons = (lessonRows as List).map((row) => AdminLessonSummary.fromRow(row as Map<String, dynamic>)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this module.';
        _loading = false;
      });
    }
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client.from('modules').update({'published': value}).eq('id', widget.moduleId);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'module.published' : 'module.unpublished',
          'p_target_type': 'module',
          'p_target_id': widget.moduleId,
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

  Future<void> _createLesson() async {
    final title = _lessonTitleController.text.trim();
    final slug = _lessonSlugController.text.trim();
    final content = _lessonContentController.text.trim();
    final minutes = int.tryParse(_lessonMinutesController.text.trim());
    if (title.isEmpty) {
      setState(() => _lessonError = 'Title is required.');
      return;
    }
    if (!isValidContentSlug(slug)) {
      setState(() => _lessonError = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (content.isEmpty) {
      setState(() => _lessonError = 'Lesson content is required.');
      return;
    }
    if (minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _lessonError = 'Minutes must be between 1 and 600.');
      return;
    }
    setState(() {
      _creatingLesson = true;
      _lessonError = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.from('lessons').insert({
        'module_id': widget.moduleId,
        'slug': slug,
        'title': title,
        'summary': _lessonSummaryController.text.trim().isEmpty ? null : _lessonSummaryController.text.trim(),
        'content_markdown': content,
        'estimated_minutes': minutes,
      });
      _lessonTitleController.clear();
      _lessonSlugController.clear();
      _lessonSummaryController.clear();
      _lessonContentController.clear();
      _lessonMinutesController.text = '10';
      _changed = true;
      final lessonRows = await client
          .from('lessons')
          .select('id, title, published, order_index')
          .eq('module_id', widget.moduleId)
          .order('order_index');
      setState(() {
        _lessons = (lessonRows as List).map((row) => AdminLessonSummary.fromRow(row as Map<String, dynamic>)).toList();
        _creatingLesson = false;
      });
    } catch (e) {
      final message = e is PostgrestException && e.code == '23505'
          ? 'That slug already exists in this module.'
          : 'Could not create the lesson.';
      setState(() {
        _lessonError = message;
        _creatingLesson = false;
      });
    }
  }

  Future<void> _openLesson(String lessonId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminLessonDetailScreen(pathId: widget.pathId, moduleId: widget.moduleId, lessonId: lessonId),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
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
        appBar: AppBar(title: Text(_title.isEmpty ? 'Module' : _title)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text('Published'),
                    value: _published,
                    onChanged: _togglePublished,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  Text('Lessons', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_lessons.isEmpty)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No lessons yet.'))
                  else
                    ..._lessons.map(
                      (l) => Card(
                        child: ListTile(
                          title: Text(l.title),
                          trailing: Chip(label: Text(l.published ? 'Published' : 'Draft')),
                          onTap: () => _openLesson(l.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New lesson'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lessonTitleController,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lessonSlugController,
                          decoration: const InputDecoration(labelText: 'Slug', hintText: 'introduction'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lessonMinutesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Estimated minutes'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lessonSummaryController,
                          maxLength: 500,
                          decoration: const InputDecoration(labelText: 'Summary'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _lessonContentController,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Content (Markdown)',
                            alignLabelWithHint: true,
                          ),
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        if (_lessonError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_lessonError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _creatingLesson ? null : _createLesson,
                          child: Text(_creatingLesson ? 'Creating...' : 'Create lesson'),
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

class AdminLessonDetailScreen extends StatefulWidget {
  const AdminLessonDetailScreen({super.key, required this.pathId, required this.moduleId, required this.lessonId});

  final String pathId;
  final String moduleId;
  final String lessonId;

  @override
  State<AdminLessonDetailScreen> createState() => _AdminLessonDetailScreenState();
}

class _AdminLessonDetailScreenState extends State<AdminLessonDetailScreen> {
  final _titleController = TextEditingController();
  final _slugController = TextEditingController();
  final _summaryController = TextEditingController();
  final _contentController = TextEditingController();
  final _minutesController = TextEditingController();

  bool _loading = true;
  bool _changed = false;
  bool _published = false;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _allSkills = const [];
  Set<String> _selectedSkillIds = {};
  bool _skillsSaving = false;
  bool _skillsSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final lessonRow = await client
          .from('lessons')
          .select('id, slug, title, summary, content_markdown, estimated_minutes, published')
          .eq('id', widget.lessonId)
          .single();
      final lesson = AdminLessonDetail.fromRow(lessonRow);
      final allSkillsRows = await client.from('skills').select('id, name').order('name');
      final lessonSkillRows = await client.from('lesson_skills').select('skill_id').eq('lesson_id', widget.lessonId);
      _titleController.text = lesson.title;
      _slugController.text = lesson.slug;
      _summaryController.text = lesson.summary ?? '';
      _contentController.text = lesson.contentMarkdown;
      _minutesController.text = lesson.estimatedMinutes.toString();
      setState(() {
        _published = lesson.published;
        _allSkills = (allSkillsRows as List).cast<Map<String, dynamic>>();
        _selectedSkillIds = (lessonSkillRows as List).map((r) => r['skill_id'] as String).toSet();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this lesson.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final content = _contentController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!isValidContentSlug(slug)) {
      setState(() => _error = 'Lowercase letters, numbers, hyphens only.');
      return;
    }
    if (content.isEmpty) {
      setState(() => _error = 'Lesson content is required.');
      return;
    }
    if (minutes == null || minutes < 1 || minutes > 600) {
      setState(() => _error = 'Minutes must be between 1 and 600.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .from('lessons')
          .update({
            'slug': slug,
            'title': title,
            'summary': _summaryController.text.trim().isEmpty ? null : _summaryController.text.trim(),
            'content_markdown': content,
            'estimated_minutes': minutes,
          })
          .eq('id', widget.lessonId);
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
      await client.from('lessons').update({'published': value}).eq('id', widget.lessonId);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'lesson.published' : 'lesson.unpublished',
          'p_target_type': 'lesson',
          'p_target_id': widget.lessonId,
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
      await client.from('lesson_skills').delete().eq('lesson_id', widget.lessonId);
      if (_selectedSkillIds.isNotEmpty) {
        await client
            .from('lesson_skills')
            .insert(_selectedSkillIds.map((skillId) => {'lesson_id': widget.lessonId, 'skill_id': skillId}).toList());
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
        appBar: AppBar(title: const Text('Lesson content')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    title: const Text('Published'),
                    value: _published,
                    onChanged: _togglePublished,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Estimated minutes'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _slugController, decoration: const InputDecoration(labelText: 'Slug')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _summaryController,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Summary'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contentController,
                    maxLines: 12,
                    decoration: const InputDecoration(labelText: 'Content (Markdown)', alignLabelWithHint: true),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save changes')),
                  const SizedBox(height: 24),
                  Text('Skills taught', style: Theme.of(context).textTheme.titleSmall),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Feeds the Skill Graph: a comprehension-check quiz tied to the same skill(s) is what '
                      'actually records "theory" evidence, not just reading this lesson.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
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
                ],
              ),
      ),
    );
  }
}
