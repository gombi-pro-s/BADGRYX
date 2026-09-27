import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'skills_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill Graph'),
        actions: [
          IconButton(
            tooltip: 'Log out ($email)',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: const SkillsScreen(),
    );
  }
}
