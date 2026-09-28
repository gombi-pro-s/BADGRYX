import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'org_detail_screen.dart';
import 'organization.dart';

/// Mirrors apps/web's lib/auth/org.ts's getUserOrganizations() exactly:
/// this user's memberships, then those organizations by id -- two plain
/// RLS-scoped queries, no Route Handler needed.
Future<List<OrgMembership>> fetchUserOrganizations(SupabaseClient client, String userId) async {
  final membershipRows = await client.from('organization_members').select('organization_id, role').eq('user_id', userId);
  final memberships = (membershipRows as List).cast<Map<String, dynamic>>();
  if (memberships.isEmpty) return [];

  final orgIds = memberships.map((m) => m['organization_id'] as String).toList();
  final orgRows = await client.from('organizations').select('id, slug, name').inFilter('id', orgIds);
  final orgById = <String, Organization>{
    for (final row in (orgRows as List).cast<Map<String, dynamic>>()) row['id'] as String: Organization.fromRow(row),
  };

  return memberships
      .map((m) => OrgMembership(role: m['role'] as String, organization: orgById[m['organization_id']]!))
      .toList();
}

/// Organizations, mobile slice: your own memberships plus a real "Create
/// organization" flow (mirrors orgs/page.tsx + create-organization-form.tsx
/// -- a plain `organizations` insert; a DB trigger makes the creator its
/// team_owner, same as web). Instructor-only features not built here yet:
/// the instructor dashboard (real member progress) and org announcement
/// management -- both stay web-only for now, named gaps rather than
/// silently missing. See ADR 0041.
class OrgsListScreen extends StatefulWidget {
  const OrgsListScreen({super.key});

  @override
  State<OrgsListScreen> createState() => _OrgsListScreenState();
}

class _OrgsListScreenState extends State<OrgsListScreen> {
  late Future<List<OrgMembership>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OrgMembership>> _load() {
    final client = Supabase.instance.client;
    return fetchUserOrganizations(client, client.auth.currentUser!.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _showCreateOrgDialog() async {
    final nameController = TextEditingController();
    final slugController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create an organization'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(
                controller: slugController,
                decoration: const InputDecoration(labelText: 'Slug', helperText: 'Lowercase letters, numbers, hyphens only.'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final slug = slugController.text.trim();
                if (name.isEmpty || !RegExp(r'^[a-z0-9-]{3,64}$').hasMatch(slug)) {
                  setDialogState(() => error = 'Enter a name and a valid slug (lowercase letters, numbers, hyphens, 3-64 chars).');
                  return;
                }
                try {
                  final client = Supabase.instance.client;
                  final row = await client
                      .from('organizations')
                      .insert({'slug': slug, 'name': name, 'created_by': client.auth.currentUser!.id})
                      .select('id')
                      .single();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  await _refresh();
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => OrgDetailScreen(organizationId: row['id'] as String)),
                  );
                } catch (e) {
                  setDialogState(
                    () => error = e.toString().contains('duplicate') ? 'That slug is already in use.' : 'Failed to create organization.',
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizations')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Create'),
        onPressed: _showCreateOrgDialog,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<OrgMembership>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(padding: const EdgeInsets.all(24), child: Text('Could not load organizations: ${snapshot.error}')),
                ],
              );
            }
            final memberships = snapshot.data!;
            if (memberships.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text("You're not a member of any organization yet. Tap Create to start one."),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: memberships.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final membership = memberships[index];
                return ListTile(
                  title: Text(membership.organization.name),
                  subtitle: Text(membership.organization.slug),
                  trailing: Chip(label: Text(formatOrgRole(membership.role))),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => OrgDetailScreen(organizationId: membership.organization.id)),
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
