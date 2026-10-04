import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/admin_screen.dart';
import '../auth/roles.dart';
import '../billing/billing_screen.dart';
import '../capstones/capstones_list_screen.dart';
import '../exams/exams_list_screen.dart';
import '../investigations/investigations_list_screen.dart';
import '../learn/learn_screen.dart';
import '../mentor/mentor_screen.dart';
import '../orgs/orgs_list_screen.dart';
import '../reports/reports_screen.dart';
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
///
/// "Admin" only appears once `fetchUserRoles()` confirms the signed-in
/// user actually holds a staff role (admin/moderator) -- the same
/// is_staff() check the web app's `/admin` layout itself enforces, read
/// here instead from `user_roles` directly since there's no middleware
/// layer on mobile to do it centrally. See ADR 0049.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static final List<_MoreItem> _baseItems = [
    _MoreItem(Icons.search_outlined, 'Investigate', (_) => const InvestigationsListScreen()),
    _MoreItem(Icons.menu_book_outlined, 'Learn', (_) => const LearnPathsListScreen()),
    _MoreItem(Icons.timer_outlined, 'Exams', (_) => const ExamsListScreen()),
    _MoreItem(Icons.school_outlined, 'Capstones', (_) => const CapstonesListScreen()),
    _MoreItem(Icons.description_outlined, 'Reports', (_) => const ReportsListScreen()),
    _MoreItem(Icons.smart_toy_outlined, 'AI Mentor', (_) => const MentorScreen()),
    _MoreItem(Icons.security_outlined, 'Security Scanner', (_) => const ScannerListScreen()),
    _MoreItem(Icons.credit_card_outlined, 'Billing', (_) => const BillingScreen()),
    _MoreItem(Icons.groups_outlined, 'Organizations', (_) => const OrgsListScreen()),
  ];

  static const _adminItem = _MoreItem(Icons.admin_panel_settings_outlined, 'Admin', _buildAdminScreen);

  static Widget _buildAdminScreen(BuildContext context) => const AdminScreen();

  late Future<bool> _isStaffFuture;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _isStaffFuture = fetchUserRoles(client, client.auth.currentUser!.id).then(isStaffRole);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isStaffFuture,
      builder: (context, snapshot) {
        final isStaff = snapshot.data ?? false;
        final items = isStaff ? [..._baseItems, _adminItem] : _baseItems;
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: item.builder)),
            );
          },
        );
      },
    );
  }
}
