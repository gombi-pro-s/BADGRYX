import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'capstone.dart';
import 'capstone_detail_screen.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'passed':
      return Colors.green;
    case 'under_review':
      return Colors.amber;
    case 'needs_revision':
      return Colors.red;
    case 'submitted':
    default:
      return Colors.grey;
  }
}

/// Mirrors apps/web's /capstones list page exactly.
Future<(List<Capstone>, Map<String, String>)> fetchCapstones(SupabaseClient client, String userId) async {
  final capstoneRows = await client
      .from('capstones')
      .select('id, title, description, report_required')
      .eq('published', true)
      .order('title');
  final submissionRows = await client
      .from('capstone_submissions')
      .select('capstone_id, status, submitted_at')
      .eq('user_id', userId)
      .order('submitted_at', ascending: false);

  final capstones = (capstoneRows as List).map((row) => Capstone.fromRow(row as Map<String, dynamic>)).toList();
  final latest = latestStatusByCapstone((submissionRows as List).cast<Map<String, dynamic>>());
  return (capstones, latest);
}

class CapstonesListScreen extends StatefulWidget {
  const CapstonesListScreen({super.key});

  @override
  State<CapstonesListScreen> createState() => _CapstonesListScreenState();
}

class _CapstonesListScreenState extends State<CapstonesListScreen> {
  late Future<(List<Capstone>, Map<String, String>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Capstone>, Map<String, String>)> _load() {
    final client = Supabase.instance.client;
    return fetchCapstones(client, client.auth.currentUser!.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capstones')),
      body: RefreshIndicator(
        onRefresh: () async {
          final next = _load();
          setState(() => _future = next);
          await next;
        },
        child: FutureBuilder<(List<Capstone>, Map<String, String>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(padding: const EdgeInsets.all(24), child: Text('Could not load capstones: ${snapshot.error}')),
                ],
              );
            }
            final (capstones, latest) = snapshot.data!;
            if (capstones.isEmpty) {
              return ListView(
                children: const [
                  Padding(padding: EdgeInsets.all(24), child: Text('No capstones are published yet.')),
                ],
              );
            }
            return ListView.separated(
              itemCount: capstones.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final capstone = capstones[index];
                final status = latest[capstone.id];
                return ListTile(
                  title: Text(capstone.title),
                  subtitle: capstone.description != null
                      ? Text(capstone.description!, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: status == null
                      ? null
                      : Text(
                          capstoneStatusLabel[status] ?? status,
                          style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600),
                        ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CapstoneDetailScreen(capstoneId: capstone.id)),
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
