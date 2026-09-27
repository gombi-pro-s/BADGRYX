import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ctf/ctf_list_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../exams/exams_list_screen.dart';
import '../investigations/investigations_list_screen.dart';
import '../labs/labs_list_screen.dart';
import 'skills_screen.dart';

const List<String> _tabTitles = [
  'Dashboard',
  'Labs',
  'Investigations',
  'Skill Graph',
  'CTF Challenges',
  'Exams',
];

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
          InvestigationsListScreen(),
          SkillsScreen(),
          CtfListScreen(),
          ExamsListScreen(),
        ],
      ),
      // 6 destinations is the practical ceiling for a bottom NavigationBar
      // before it gets cramped on narrow phones -- a real UX concern to
      // revisit (e.g. a Drawer or NavigationRail) once more tabs are added,
      // not silently ignored, see ADR 0031.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.terminal_outlined), label: 'Labs'),
          NavigationDestination(icon: Icon(Icons.search_outlined), label: 'Investigate'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Skills'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), label: 'CTF'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Exams'),
        ],
      ),
    );
  }
}
