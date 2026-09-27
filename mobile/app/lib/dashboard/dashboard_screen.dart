import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'announcement.dart';

class DashboardData {
  DashboardData({required this.displayName, required this.planName, required this.announcements});

  final String displayName;
  final String planName;
  final List<Announcement> announcements;
}

/// Mirrors apps/web's dashboard/page.tsx queries exactly: the user's own
/// profile display name, their active/trialing/past_due subscription's
/// joined plan name (or "Free"), and up to 5 published, non-expired
/// announcements -- RLS already scopes org announcements to orgs this
/// user belongs to.
Future<DashboardData> fetchDashboard(SupabaseClient client, String userId, String fallbackName) async {
  final nowIso = DateTime.now().toUtc().toIso8601String();

  final profileRow = await client.from('profiles').select('display_name').eq('id', userId).maybeSingle();
  final subscriptionRow = await client
      .from('subscriptions')
      .select('plan_id, status, plans(name, slug)')
      .eq('subject_type', 'user')
      .eq('subject_id', userId)
      .inFilter('status', ['trialing', 'active', 'past_due'])
      .maybeSingle();
  final announcementRows = await client
      .from('announcements')
      .select('id, title, body_markdown, published_at')
      .eq('published', true)
      .or('expires_at.is.null,expires_at.gt.$nowIso')
      .order('published_at', ascending: false)
      .limit(5);

  return DashboardData(
    displayName: (profileRow?['display_name'] as String?) ?? fallbackName,
    planName: planNameFromSubscriptionRow(subscriptionRow),
    announcements: (announcementRows as List).map((row) => Announcement.fromRow(row as Map<String, dynamic>)).toList(),
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DashboardData> _load() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser!;
    return fetchDashboard(client, user.id, user.email ?? 'there');
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() => _future = next);
        await next;
      },
      child: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(padding: const EdgeInsets.all(24), child: Text('Could not load your dashboard: ${snapshot.error}')),
              ],
            );
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Welcome back, ${data.displayName}', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text("You're on the ${data.planName} plan."),
              if (data.announcements.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Announcements', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...data.announcements.map(
                  (a) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(a.bodyMarkdown),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
