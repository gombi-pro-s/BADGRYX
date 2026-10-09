import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'privacy.dart';

/// Mirrors `/settings/privacy`'s own two sections: export your data and
/// delete your account. Both are Bearer-authed Route Handler calls
/// (`GET`/`POST /api/account/export`/`/delete`), not plain Postgrest --
/// export reads 19 tables the caller doesn't otherwise have a single
/// RLS-scoped read for, and deletion needs the GoTrue Admin API
/// (`service_role`), which only a server can hold. Both routes call the
/// exact same shared TypeScript functions
/// (`lib/account/delete-account.ts`) the web Server Actions already
/// used -- see ADR 0033/0067. Degrades to a plain "not configured on
/// this build" message without `API_BASE_URL`, the same pattern as
/// Billing/Mentor/Scanner.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _exporting = false;
  String? _exportError;

  bool _deleteExpanded = false;
  final _confirmationController = TextEditingController();
  bool _deleting = false;
  String? _deleteError;

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  /// GETs `/api/account/export` with the session's Bearer token and
  /// shows the returned JSON bundle in a copy-to-clipboard dialog --
  /// same pattern as the admin Learning Paths screen's path export.
  Future<void> _exportData() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _exportError = 'Your session has expired. Please log in again.');
      return;
    }
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${AppEnv.apiBaseUrl}/api/account/export'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Export failed (${response.statusCode}).');
      }
      setState(() => _exporting = false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Your data'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(response.body, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: response.body)),
              child: const Text('Copy to clipboard'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _exportError = e.toString().replaceFirst('Exception: ', '');
        _exporting = false;
      });
    }
  }

  /// POSTs `/api/account/delete` with the session's Bearer token once
  /// `confirmsAccountDeletion()` passes client-side -- a mismatch never
  /// even reaches the network. On success, signs out locally (the
  /// account is already gone server-side) so `AuthGate` shows the login
  /// screen again, the same end state web's own redirect to
  /// `/login?deleted=1` reaches.
  Future<void> _deleteAccount() async {
    if (!confirmsAccountDeletion(_confirmationController.text, _email)) {
      setState(() => _deleteError = 'Type your account email exactly to confirm.');
      return;
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _deleteError = 'Your session has expired. Please log in again.');
      return;
    }
    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${AppEnv.apiBaseUrl}/api/account/delete'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
        body: jsonEncode({'confirmation': _confirmationController.text}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['error'] as String? ?? 'Could not delete your account (${response.statusCode}).');
      }
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      setState(() {
        _deleteError = e.toString().replaceFirst('Exception: ', '');
        _deleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!AppEnv.isApiConfigured)
            const Text(
              "Privacy & data isn't configured on this build. Run with --dart-define=API_BASE_URL=... to "
              'enable it. See mobile/app/README.md.',
              style: TextStyle(fontSize: 12),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Export your data', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'Download everything tied to your account -- profile, skill graph, lab/quiz/CTF/'
                    'investigation/capstone history, mentor conversations, scanner scans, and subscription '
                    'history -- as JSON.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (_exportError != null) ...[
                    Text(_exportError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: _exporting ? null : _exportData,
                    child: Text(_exporting ? 'Exporting...' : 'Export my data'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete account',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Permanently deletes your account. This cannot be undone.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (!_deleteExpanded)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                      onPressed: () => setState(() => _deleteExpanded = true),
                      child: const Text('Delete my account'),
                    )
                  else ...[
                    Text(
                      'This permanently deletes your account and every piece of data tied to it -- your '
                      'profile, skill graph, lab and quiz history, CTF and investigation submissions, mentor '
                      'conversations, scans, and subscription. This cannot be undone.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmationController,
                      decoration: InputDecoration(labelText: 'Type ${_email ?? "your email"} to confirm'),
                    ),
                    if (_deleteError != null) ...[
                      const SizedBox(height: 8),
                      Text(_deleteError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                          onPressed: _deleting ? null : _deleteAccount,
                          child: Text(_deleting ? 'Deleting...' : 'Permanently delete my account'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _deleting
                              ? null
                              : () => setState(() {
                                  _deleteExpanded = false;
                                  _confirmationController.clear();
                                  _deleteError = null;
                                }),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
