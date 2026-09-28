import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'scan.dart';

/// Mirrors apps/web's /scanner/[scanId] page's queries: the scan itself,
/// its findings (most-severe-first, then by line), and a file-id ->
/// filename lookup so each finding can show "filename:line".
Future<(Scan, List<ScanFinding>, Map<String, String>)> fetchScanDetail(SupabaseClient client, String scanId) async {
  final scanRow = await client
      .from('scans')
      .select('id, title, status, total_files, total_findings, findings_by_severity, error_message, created_at')
      .eq('id', scanId)
      .single();
  final findingRows = await client
      .from('scan_findings')
      .select(
        'id, file_id, rule_id, category, title, severity, confidence, line_start, line_end, evidence, explanation, impact, remediation, secure_example, verification_status, ai_enriched, status',
      )
      .eq('scan_id', scanId)
      .order('severity', ascending: true)
      .order('line_start', ascending: true);
  final fileRows = await client.from('scan_files').select('id, filename').eq('scan_id', scanId);

  final scan = Scan.fromRow(scanRow);
  final findings = (findingRows as List).map((row) => ScanFinding.fromRow(row as Map<String, dynamic>)).toList();
  final filenameById = <String, String>{
    for (final row in (fileRows as List).cast<Map<String, dynamic>>()) row['id'] as String: row['filename'] as String,
  };
  return (scan, findings, filenameById);
}

Color _severityColor(String severity) {
  switch (severity) {
    case 'critical':
      return Colors.red.shade900;
    case 'high':
      return Colors.red;
    case 'medium':
      return Colors.orange;
    case 'low':
      return Colors.amber;
    case 'info':
    default:
      return Colors.blueGrey;
  }
}

/// Findings support real manual status transitions
/// (transition_scan_finding_status() RPC, plain RLS-scoped, no Route
/// Handler needed -- see ADR 0044) and real "Enrich with AI"
/// (`/api/scanner/findings/{id}/enrich`, Bearer-authed like Mentor/scan-
/// submission/the lab terminal, degrading to a disabled button with an
/// explanatory tooltip when the app is built without `API_BASE_URL` --
/// see ADR 0045). Multi-file upload on the "New scan" screen remains the
/// one named gap left from ADR 0036.
class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.scanId});

  final String scanId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  late Future<(Scan, List<ScanFinding>, Map<String, String>)> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchScanDetail(Supabase.instance.client, widget.scanId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan results')),
      body: FutureBuilder<(Scan, List<ScanFinding>, Map<String, String>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Could not load this scan: ${snapshot.error}'));
          }
          final (scan, findings, filenameById) = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(scan.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${scan.totalFiles} file${scan.totalFiles == 1 ? '' : 's'} scanned · '
                '${formatScanTimestamp(scan.createdAt)} · ${scan.status}',
              ),
              if (scan.status == 'failed')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Scan failed: ${scan.errorMessage ?? "Unknown error."}'),
                  ),
                ),
              const SizedBox(height: 16),
              if (findings.isEmpty)
                Text(
                  scan.status == 'completed'
                      ? 'No findings -- the deterministic rule engine found nothing to flag in this scan.'
                      : 'This scan has no findings yet.',
                )
              else
                ...findings.map((finding) => _FindingCard(finding: finding, filename: filenameById[finding.fileId] ?? 'unknown file')),
            ],
          );
        },
      ),
    );
  }
}

class _FindingCard extends StatefulWidget {
  const _FindingCard({required this.finding, required this.filename});

  final ScanFinding finding;
  final String filename;

  @override
  State<_FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<_FindingCard> {
  bool _expanded = false;
  late String _status;
  late String _explanation;
  late String _impact;
  late String _remediation;
  late String? _secureExample;
  late bool _aiEnriched;
  String? _transitioning;
  bool _enriching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.finding.status;
    _explanation = widget.finding.explanation;
    _impact = widget.finding.impact;
    _remediation = widget.finding.remediation;
    _secureExample = widget.finding.secureExample;
    _aiEnriched = widget.finding.aiEnriched;
  }

  Future<void> _transition(String newStatus) async {
    setState(() {
      _transitioning = newStatus;
      _error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc(
        'transition_scan_finding_status',
        params: {'p_finding_id': widget.finding.id, 'p_new_status': newStatus},
      );
      setState(() {
        _status = (result as Map<String, dynamic>)['status'] as String;
        _transitioning = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not update status.';
        _transitioning = null;
      });
    }
  }

  Future<void> _enrich() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _error = 'Your session has expired. Please log in again.');
      return;
    }
    setState(() {
      _enriching = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${AppEnv.apiBaseUrl}/api/scanner/findings/${widget.finding.id}/enrich'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['error'] as String? ?? 'Enrichment failed (${response.statusCode}).');
      }
      final finding = body['finding'] as Map<String, dynamic>;
      setState(() {
        _explanation = finding['explanation'] as String;
        _impact = finding['impact'] as String;
        _remediation = finding['remediation'] as String;
        _secureExample = finding['secure_example'] as String?;
        _aiEnriched = true;
        _enriching = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _enriching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final finding = widget.finding;
    final nextStatuses = legalStatusTransitions[_status] ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _severityColor(finding.severity).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    severityLabel[finding.severity] ?? finding.severity,
                    style: TextStyle(color: _severityColor(finding.severity), fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(findingStatusLabel[_status] ?? _status, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (_aiEnriched) ...[
                  const SizedBox(width: 8),
                  Text('AI-enriched', style: Theme.of(context).textTheme.bodySmall),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
            Text(finding.title, style: Theme.of(context).textTheme.titleSmall),
            Text(
              '${widget.filename}:${finding.lineStart}'
              '${finding.lineEnd != finding.lineStart ? '-${finding.lineEnd}' : ''} · ${finding.ruleId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_expanded) ...[
              const Divider(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(finding.evidence, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              const SizedBox(height: 10),
              _Section(title: 'Explanation', body: _explanation),
              _Section(title: 'Impact', body: _impact),
              _Section(title: 'Remediation', body: _remediation),
              if (_secureExample != null) ...[
                const SizedBox(height: 8),
                Text('Secure example', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_secureExample!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
              if (nextStatuses.isNotEmpty || AppEnv.isApiConfigured) const Divider(height: 20),
              if (nextStatuses.isNotEmpty || AppEnv.isApiConfigured)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...nextStatuses.map((next) {
                      return OutlinedButton(
                        onPressed: _transitioning != null ? null : () => _transition(next),
                        child: Text(_transitioning == next ? 'Updating...' : statusActionLabel[next] ?? next),
                      );
                    }),
                    if (AppEnv.isApiConfigured)
                      FilledButton.tonal(
                        onPressed: _enriching ? null : _enrich,
                        child: Text(_enriching ? 'Enriching...' : 'Enrich with AI'),
                      ),
                  ],
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          Text(body),
        ],
      ),
    );
  }
}
