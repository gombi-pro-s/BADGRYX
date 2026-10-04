import 'package:flutter/material.dart';

import 'admin_announcements_screen.dart';
import 'admin_users_screen.dart';

/// The mobile landing page for `/admin`'s own sidebar -- reachable only
/// when the More screen's isStaffRole() gate passed, so this app never
/// needs to check staff standing a second time just to show this list.
/// Platform Announcements and Users are the admin CMS flows ported to
/// mobile so far; every other `/admin/*` section (learning paths, labs,
/// quizzes, CTF challenges, CTF events, path import/export, report
/// moderation) has no mobile screen yet -- a real, deliberately broad
/// remaining gap, not silently missing. See ADR 0049/0051.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Platform Announcements'),
            subtitle: const Text("Shown on every learner's dashboard"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminAnnouncementsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Users'),
            subtitle: const Text('Grant or revoke instructor/moderator/admin roles'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
