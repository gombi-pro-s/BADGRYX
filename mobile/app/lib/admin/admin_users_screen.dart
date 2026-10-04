import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_user.dart';

/// Mirrors admin/users/page.tsx + actions.ts + user-search.tsx +
/// role-toggle.tsx: search any user by email/username/display name, then
/// grant/revoke their instructor/moderator/admin roles. Every write goes
/// through `grant_platform_role()`/`revoke_platform_role()`, which audit-
/// log themselves and re-check `is_admin()` server-side regardless of
/// this screen's own `isStaffRole()` gate (the More screen's entry
/// point) -- the real authorization boundary, same as every other admin
/// RPC in this app. See ADR 0051.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _queryController = TextEditingController();
  List<AdminUserSearchResult> _results = [];
  bool _searching = false;
  String? _error;
  final Set<String> _pendingToggleKeys = {};

  String get _currentAdminId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client.rpc(
        'admin_search_users',
        params: {'p_query': _queryController.text.trim()},
      );
      setState(() => _results = (rows as List).map((row) => AdminUserSearchResult.fromRow(row as Map<String, dynamic>)).toList());
    } catch (e) {
      setState(() => _error = 'Could not search users.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggleRole(AdminUserSearchResult user, String role, bool grant) async {
    final key = '${user.userId}:$role';
    setState(() {
      _pendingToggleKeys.add(key);
      if (grant) {
        user.roles.add(role);
      } else {
        user.roles.remove(role);
      }
    });
    try {
      if (grant) {
        await Supabase.instance.client.rpc('grant_platform_role', params: {'p_user_id': user.userId, 'p_role': role});
      } else {
        await Supabase.instance.client.rpc('revoke_platform_role', params: {'p_user_id': user.userId, 'p_role': role});
      }
    } catch (e) {
      // Revert on failure -- mirrors role-toggle.tsx's optimistic-then-revert.
      setState(() {
        if (grant) {
          user.roles.remove(role);
        } else {
          user.roles.add(role);
        }
        _error = 'Could not change that role.';
      });
    } finally {
      if (mounted) setState(() => _pendingToggleKeys.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Grant or revoke instructor/moderator/admin roles. Every change is audit-logged, and you can '
            "never revoke your own admin role from here.",
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search by email, username, or display name',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _search,
                child: Text(_searching ? '...' : 'Search'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          if (_results.isEmpty)
            Text(
              _searching ? '' : 'Search for a user to view or change their roles.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._results.map((user) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.label, style: Theme.of(context).textTheme.titleSmall),
                      if (user.email != null)
                        Text(user.email!, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: grantableRoles.map((role) {
                          final granted = user.roles.contains(role);
                          final disabled = isRoleToggleDisabled(
                            role: role,
                            userId: user.userId,
                            currentAdminId: _currentAdminId,
                          );
                          final pending = _pendingToggleKeys.contains('${user.userId}:$role');
                          return FilterChip(
                            label: Text(role),
                            selected: granted,
                            onSelected: (disabled || pending) ? null : (value) => _toggleRole(user, role, value),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
