import 'package:flutter/material.dart';
import '../capstones/capstones_list_screen.dart';
import '../exams/exams_list_screen.dart';
import '../investigations/investigations_list_screen.dart';
import '../mentor/mentor_screen.dart';
import '../scanner/scanner_list_screen.dart';

class _MoreItem {
  const _MoreItem(this.icon, this.label, this.builder);

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// A plain menu of the tabs that don't fit on the bottom NavigationBar
/// (Material's practical ceiling is around 5 destinations before it gets
/// cramped on a phone -- see ADR 0032). Each of these was a first-class
/// bottom-nav tab in an earlier phase; this is a real navigation
/// restructuring, not a demotion of the features themselves.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static final List<_MoreItem> _items = [
    _MoreItem(Icons.search_outlined, 'Investigate', (_) => const InvestigationsListScreen()),
    _MoreItem(Icons.timer_outlined, 'Exams', (_) => const ExamsListScreen()),
    _MoreItem(Icons.school_outlined, 'Capstones', (_) => const CapstonesListScreen()),
    _MoreItem(Icons.smart_toy_outlined, 'AI Mentor', (_) => const MentorScreen()),
    _MoreItem(Icons.security_outlined, 'Security Scanner', (_) => const ScannerListScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          leading: Icon(item.icon),
          title: Text(item.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: item.builder)),
        );
      },
    );
  }
}
