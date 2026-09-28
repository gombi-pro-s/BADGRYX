import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'instructor_dashboard_screen.dart';
import 'org_announcements_screen.dart';
import 'organization.dart';

class OrgDetailData {
  OrgDetailData({
    required this.organization,
    required this.myRole,
    required this.members,
    required this.displayNameByUserId,
    required this.invitations,
  });

  final Organization organization;
  final String myRole;
  final List<OrganizationMember> members;
  final Map<String, String> displayNameByUserId;
  final List<OrganizationInvitation>? invitations; // null unless I'm an admin
}

/// Mirrors orgs/[orgId]/page.tsx's queries exactly, including the RLS-only
/// visibility of invitations (a plain member's own query for
/// organization_invitations returns empty -- that's org_invitations_select
/// _org_admin doing its job, not a bug to route around client-side).
Future<OrgDetailData> fetchOrgDetail(SupabaseClient client, String organizationId, String myUserId) async {
  final orgRow = await client.from('organizations').select('id, slug, name').eq('id', organizationId).single();
  final memberRows = await client
      .from('organization_members')
      .select('id, user_id, role, joined_at')
      .eq('organization_id', organizationId)
      .order('joined_at');
  final members = (memberRows as List).map((row) => OrganizationMember.fromRow(row as Map<String, dynamic>)).toList();

  final myMemberships = members.where((m) => m.userId == myUserId);
  final myRole = myMemberships.isEmpty ? 'member' : myMemberships.first.role;

  final userIds = members.map((m) => m.userId).toList();
  final profileRows = userIds.isEmpty
      ? []
      : await client.from('profiles').select('id, display_name, username').inFilter('id', userIds);
  final displayNameByUserId = <String, String>{
    for (final row in profileRows.cast<Map<String, dynamic>>())
      row['id'] as String: (row['display_name'] as String?) ?? (row['username'] as String?) ?? row['id'] as String,
  };

  List<OrganizationInvitation>? invitations;
  if (isOrgAdminRole(myRole)) {
    final invitationRows = await client
        .from('organization_invitations')
        .select('id, email, role, expires_at, accepted_at, revoked_at')
        .eq('organization_id', organizationId)
        .order('created_at', ascending: false);
    invitations = (invitationRows as List).map((row) => OrganizationInvitation.fromRow(row as Map<String, dynamic>)).toList();
  }

  return OrgDetailData(
    organization: Organization.fromRow(orgRow),
    myRole: myRole,
    members: members,
    displayNameByUserId: displayNameByUserId,
    invitations: invitations,
  );
}

/// Mirrors orgs/[orgId]/page.tsx: role badge, member roster (admins can
/// change roles/remove members; anyone can leave), and, for admins, a real
/// invite-link flow (create_organization_invitation RPC) and revoke list.
/// Instructors+ also get the real instructor dashboard and announcement
/// authoring; see ADR 0041/0042/0043.
class OrgDetailScreen extends StatefulWidget {
  const OrgDetailScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<OrgDetailScreen> createState() => _OrgDetailScreenState();
}

class _OrgDetailScreenState extends State<OrgDetailScreen> {
  late Future<OrgDetailData> _future;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<OrgDetailData> _load() {
    final client = Supabase.instance.client;
    return fetchOrgDetail(client, widget.organizationId, client.auth.currentUser!.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
      _error = null;
    });
    await next;
  }

  Future<void> _updateMemberRole(String memberId, String newRole) async {
    try {
      await Supabase.instance.client.rpc(
        'update_organization_member_role',
        params: {'p_organization_id': widget.organizationId, 'p_organization_member_id': memberId, 'p_new_role': newRole},
      );
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Failed to update role.');
    }
  }

  Future<void> _removeMember(String memberId, bool isSelf) async {
    try {
      await Supabase.instance.client.rpc(
        'remove_organization_member',
        params: {'p_organization_id': widget.organizationId, 'p_organization_member_id': memberId},
      );
      if (isSelf) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await _refresh();
    } catch (e) {
      setState(() => _error = isSelf ? 'Failed to leave.' : 'Failed to remove member.');
    }
  }

  Future<void> _revokeInvitation(String invitationId) async {
    try {
      await Supabase.instance.client
          .from('organization_invitations')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', invitationId);
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Failed to revoke invitation.');
    }
  }

  Future<void> _showInviteDialog() async {
    final emailController = TextEditingController();
    String role = 'member';
    String? dialogError;
    String? inviteLink;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite a member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (inviteLink == null) ...[
                const Text(
                  'There is no email service wired up -- the invite link is shown once below. Copy it and '
                  'send it to the invitee yourself.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: allOrgRoles.map((r) => DropdownMenuItem(value: r, child: Text(formatOrgRole(r)))).toList(),
                  onChanged: (value) => setDialogState(() => role = value ?? role),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ] else ...[
                const Text(
                  'Invite link created -- this is the only time it will be shown. Copy it now.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 8),
                SelectableText(inviteLink!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ],
          ),
          actions: inviteLink == null
              ? [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            final email = emailController.text.trim();
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                              setDialogState(() => dialogError = 'Enter a valid email address.');
                              return;
                            }
                            setDialogState(() => submitting = true);
                            try {
                              final token = await Supabase.instance.client.rpc(
                                'create_organization_invitation',
                                params: {'p_organization_id': widget.organizationId, 'p_email': email, 'p_role': role},
                              );
                              final baseUrl = AppEnv.apiBaseUrl;
                              setDialogState(
                                () => inviteLink = baseUrl.isNotEmpty ? '$baseUrl/invite/$token' : token as String,
                              );
                              await _refresh();
                            } catch (e) {
                              setDialogState(() {
                                dialogError = 'Failed to create invitation.';
                                submitting = false;
                              });
                            }
                          },
                    child: Text(submitting ? 'Creating...' : 'Create invite link'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Clipboard.setData(ClipboardData(text: inviteLink!)),
                    child: const Text('Copy'),
                  ),
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organization')),
      body: FutureBuilder<OrgDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this organization: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final myUserId = Supabase.instance.client.auth.currentUser!.id;
          final isAdmin = isOrgAdminRole(data.myRole);
          final isInstructor = isOrgInstructorRole(data.myRole);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.organization.name, style: Theme.of(context).textTheme.headlineSmall),
                          Text(data.organization.slug, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Chip(label: Text(formatOrgRole(data.myRole))),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (isInstructor) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.insights_outlined),
                        label: const Text('Open instructor dashboard'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => InstructorDashboardScreen(organizationId: widget.organizationId)),
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.campaign_outlined),
                        label: const Text('Announcements'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => OrgAnnouncementsScreen(organizationId: widget.organizationId)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text('Members (${data.members.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: data.members.map((member) {
                      final isSelf = member.userId == myUserId;
                      final name = data.displayNameByUserId[member.userId] ?? member.userId;
                      return ListTile(
                        title: Text(isSelf ? '$name (you)' : name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isAdmin)
                              DropdownButton<String>(
                                value: member.role,
                                items: allOrgRoles.map((r) => DropdownMenuItem(value: r, child: Text(formatOrgRole(r)))).toList(),
                                onChanged: (value) {
                                  if (value != null && value != member.role) _updateMemberRole(member.id, value);
                                },
                              )
                            else
                              Text(formatOrgRole(member.role)),
                            if (isAdmin || isSelf)
                              IconButton(
                                icon: const Icon(Icons.person_remove_outlined, size: 20),
                                tooltip: isSelf ? 'Leave' : 'Remove',
                                onPressed: () => _confirmRemove(member.id, isSelf),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Invite a member'),
                    onPressed: _showInviteDialog,
                  ),
                  if (data.invitations != null && data.invitations!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Invitations', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: data.invitations!.map((invitation) {
                          final status = invitationStatus(invitation, DateTime.now());
                          return ListTile(
                            title: Text(invitation.email),
                            subtitle: Text('${formatOrgRole(invitation.role)} · $status'),
                            trailing: status == 'Pending'
                                ? TextButton(onPressed: () => _revokeInvitation(invitation.id), child: const Text('Revoke'))
                                : null,
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(String memberId, bool isSelf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isSelf ? 'Leave organization?' : 'Remove member?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirmed == true) await _removeMember(memberId, isSelf);
  }
}
