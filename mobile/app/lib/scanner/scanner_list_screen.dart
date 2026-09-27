import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'new_scan_screen.dart';
import 'scan.dart';
import 'scan_detail_screen.dart';

/// Mirrors apps/web's /scanner list page's query exactly.
Future<List<Scan>> fetchScans(SupabaseClient client, String userId) async {
  final rows = await client
      .from('scans')
      .select('id, title, status, total_files, total_findings, findings_by_severity, error_message, created_at')
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(20);
  return (rows as List).map((row) => Scan.fromRow(row as Map<String, dynamic>)).toList();
}

/// Security Scanner, mobile slice: past scans + a combined posture summary
/// (same aggregatePosture() logic as apps/web's inline calc), and a "New
/// scan" entry point for a pasted-code scan. Read-only findings (no
/// enrich-with-AI or manual status-transition actions yet -- an honest
/// scope boundary, mirroring the terminal-backed labs' "not on mobile yet"
/// banner) -- see ADR 0036.
class ScannerListScreen extends StatefulWidget {
  const ScannerListScreen({super.key});

  @override
  State<ScannerListScreen> createState() => _ScannerListScreenState();
}

class _ScannerListScreenState extends State<ScannerListScreen> {
  late Future<List<Scan>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Scan>> _load() {
    final client = Supabase.instance.client;
    return fetchScans(client, client.auth.currentUser!.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Scanner')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New scan'),
        onPressed: () async {
          final started = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const NewScanScreen()),
          );
          if (started == true) await _refresh();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Scan>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(padding: const EdgeInsets.all(24), child: Text('Could not load scans: ${snapshot.error}')),
                ],
              );
            }
            final scans = snapshot.data!;
            if (scans.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No scans yet. Tap "New scan" to paste code for your first scan.'),
                  ),
                ],
              );
            }
            final posture = aggregatePosture(scans);
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _PostureSummary(posture: posture),
                ),
                const Divider(height: 1),
                ...scans.map(
                  (scan) => ListTile(
                    title: Text(scan.title),
                    subtitle: Text(
                      '${scan.totalFiles} file${scan.totalFiles == 1 ? '' : 's'} · '
                      '${scan.totalFindings} finding${scan.totalFindings == 1 ? '' : 's'} · '
                      '${formatScanTimestamp(scan.createdAt)}',
                    ),
                    trailing: Text(scan.status.toUpperCase(), style: Theme.of(context).textTheme.bodySmall),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ScanDetailScreen(scanId: scan.id)),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PostureSummary extends StatelessWidget {
  const _PostureSummary({required this.posture});

  final Map<String, int> posture;

  @override
  Widget build(BuildContext context) {
    final present = severityOrder.where((sev) => (posture[sev] ?? 0) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Posture across your recent scans', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (present.isEmpty)
          const Text('No findings yet across these scans -- clean.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: present
                .map((sev) => Chip(label: Text('${severityLabel[sev] ?? sev}: ${posture[sev]}')))
                .toList(),
          ),
      ],
    );
  }
}
