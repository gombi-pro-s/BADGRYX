import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ctf/ctf_list_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../labs/labs_list_screen.dart';
import 'more_screen.dart';
import 'skills_screen.dart';

const List<String> _tabTitles = ['Dashboard', 'Labs', 'Skill Graph', 'CTF Challenges', 'More'];

/// Five bottom-nav destinations: the tabs used most often stay directly
/// reachable, and everything else (Investigate, Exams, Capstones, and
/// wherever Capstones/Mentor/Scanner/Billing land later) lives behind
/// "More" -- see ADR 0032 for why this replaced the growing flat tab bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitles[_index]),
        actions: [
          IconButton(
            tooltip: 'Log out ($email)',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          LabsListScreen(),
          SkillsScreen(),
          CtfListScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), label: 'Labs'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Skills'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'CTF'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
