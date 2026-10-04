import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../orgs/org_announcement.dart';

/// Mirrors admin/announcements/page.tsx + [announcementId]/page.tsx +
/// actions.ts -- the platform-wide (`organization_id IS NULL`) twin of
/// orgs/[orgId]/announcements, reusing `OrgAnnouncement` and its pure
/// helpers as-is (the model has no org-specific fields; only the query/
/// mutation scope differs). Restricted to staff by the caller (the More
/// screen's isStaffRole() gate, same as the web page's own requireAdmin()
/// at the action level) -- `announcements_write` already restricts a
/// platform-wide write to staff regardless, so there is no separate
/// authorization check to port here. See ADR 0049.
Future<List<OrgAnnouncement>> fetchAdminAnnouncements(SupabaseClient client) async {
  final rows = await client
      .from('announcements')
      .select('id, title, body_markdown, published, published_at, expires_at, created_at')
      .isFilter('organization_id', null)
      .order('created_at', ascending: false);
  return (rows as List).map((row) => OrgAnnouncement.fromRow(row as Map<String, dynamic>)).toList();
}

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  late Future<List<OrgAnnouncement>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchAdminAnnouncements(Supabase.instance.client);
  }

  Future<void> _refresh() async {
    final next = fetchAdminAnnouncements(Supabase.instance.client);
    setState(() => _future = next);
    await next;
  }

  Future<void> _openForm({String? announcementId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminAnnouncementFormScreen(announcementId: announcementId)),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform Announcements')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'New announcement',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<OrgAnnouncement>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Could not load announcements: ${snapshot.error}'));
            }
            final announcements = snapshot.data ?? [];
            if (announcements.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No platform announcements yet. Create the first one with the + button.'),
                  ),
                ],
              );
            }
            final now = DateTime.now();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: announcements.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final announcement = announcements[index];
                final status = announcementStatusLabel(announcement, now);
                return Card(
                  child: ListTile(
                    title: Text(announcement.title),
                    trailing: Chip(label: Text(status)),
                    onTap: () => _openForm(announcementId: announcement.id),
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

/// Create when `announcementId` is null, edit otherwise -- same reasoning
/// as OrgAnnouncementFormScreen for combining the web's two pages into one
/// screen here.
class AdminAnnouncementFormScreen extends StatefulWidget {
  const AdminAnnouncementFormScreen({super.key, this.announcementId});

  final String? announcementId;

  @override
  State<AdminAnnouncementFormScreen> createState() => _AdminAnnouncementFormScreenState();
}

class _AdminAnnouncementFormScreenState extends State<AdminAnnouncementFormScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _titleEsController = TextEditingController();
  final _bodyEsController = TextEditingController();
  DateTime? _expiresAt;
  bool _published = false;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  bool get _isEditing => widget.announcementId != null;

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
          .from('announcements')
          .select('id, title, body_markdown, published, expires_at')
          .eq('id', widget.announcementId!)
          .isFilter('organization_id', null)
          .single();
      final announcement = OrgAnnouncement.fromRow({...row, 'created_at': DateTime.now().toIso8601String()});
      _titleController.text = announcement.title;
      _bodyController.text = announcement.bodyMarkdown;
      final translationRow = await Supabase.instance.client
          .from('announcement_translations')
          .select('title, body_markdown')
          .eq('announcement_id', widget.announcementId!)
          .eq('locale', 'es')
          .maybeSingle();
      if (translationRow != null) {
        _titleEsController.text = translationRow['title'] as String;
        _bodyEsController.text = translationRow['body_markdown'] as String;
      }
      setState(() {
        _published = announcement.published;
        _expiresAt = announcement.expiresAt;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load this announcement.';
        _loading = false;
      });
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_expiresAt ?? now));
    if (time == null) return;
    setState(() => _expiresAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Title and body are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      String announcementId;
      if (_isEditing) {
        announcementId = widget.announcementId!;
        await client
            .from('announcements')
            .update({'title': title, 'body_markdown': body, 'expires_at': _expiresAt?.toUtc().toIso8601String()})
            .eq('id', announcementId);
      } else {
        final created = await client
            .from('announcements')
            .insert({
              'title': title,
              'body_markdown': body,
              'expires_at': _expiresAt?.toUtc().toIso8601String(),
              'created_by': client.auth.currentUser!.id,
            })
            .select('id')
            .single();
        announcementId = created['id'] as String;
      }
      await _upsertSpanishTranslation(client, announcementId, _titleEsController.text.trim(), _bodyEsController.text.trim());
      _changed = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = _isEditing ? 'Could not save changes.' : 'Could not create the announcement.';
        _saving = false;
      });
    }
  }

  /// Mirrors admin/announcements/actions.ts's upsertSpanishTranslation()
  /// exactly -- see org_announcements_screen.dart's own copy for why only
  /// 'es' exists.
  Future<void> _upsertSpanishTranslation(SupabaseClient client, String announcementId, String titleEs, String bodyEs) {
    if (shouldUpsertSpanishTranslation(titleEs, bodyEs)) {
      return client.from('announcement_translations').upsert(
        {'announcement_id': announcementId, 'locale': 'es', 'title': titleEs, 'body_markdown': bodyEs},
        onConflict: 'announcement_id,locale',
      );
    }
    return client.from('announcement_translations').delete().eq('announcement_id', announcementId).eq('locale', 'es');
  }

  Future<void> _togglePublished(bool value) async {
    final client = Supabase.instance.client;
    try {
      await client
          .from('announcements')
          .update({'published': value, 'published_at': value ? DateTime.now().toUtc().toIso8601String() : null})
          .eq('id', widget.announcementId!);
      await client.rpc(
        'log_audit_event',
        params: {
          'p_action': value ? 'announcement.published' : 'announcement.unpublished',
          'p_target_type': 'announcement',
          'p_target_id': widget.announcementId,
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this announcement?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.from('announcements').delete().eq('id', widget.announcementId!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not delete this announcement.');
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
          title: Text(_isEditing ? 'Edit announcement' : 'New announcement'),
          actions: _isEditing
              ? [IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _confirmDelete)]
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isEditing) ...[
                    SwitchListTile(
                      title: const Text('Published'),
                      subtitle: const Text("Shown on every learner's dashboard while on and not expired."),
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
                    controller: _bodyController,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Body (markdown)', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _expiresAt == null ? 'No expiry set' : 'Expires ${_expiresAt!.toLocal()}'.split('.').first,
                        ),
                      ),
                      TextButton(onPressed: _pickExpiry, child: const Text('Set expiry')),
                      if (_expiresAt != null)
                        TextButton(onPressed: () => setState(() => _expiresAt = null), child: const Text('Clear')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Spanish translation (optional) -- shown instead of the text above when a member's "
                          'language is set to Spanish. Leave blank for no translation.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _titleEsController,
                          maxLength: 200,
                          decoration: const InputDecoration(labelText: 'Title (Spanish)'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bodyEsController,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Body (Spanish, markdown)',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : (_isEditing ? 'Save changes' : 'Post announcement')),
                  ),
                ],
              ),
      ),
    );
  }
}
