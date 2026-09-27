import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'scan_detail_screen.dart';

/// Pasted-snippet scans only -- `uploaded_files` needs a file picker,
/// deferred for the same reason terminal-backed labs show a "not on
/// mobile yet" banner rather than a half-built alternative. Submits via
/// the same requireApiUser() Bearer-token path ADR 0033/0035 built for
/// /api/scanner/scan.
class NewScanScreen extends StatefulWidget {
  const NewScanScreen({super.key});

  @override
  State<NewScanScreen> createState() => _NewScanScreenState();
}

class _NewScanScreenState extends State<NewScanScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController(text: 'snippet.js');
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final filename = _filenameController.text.trim();
    if (code.isEmpty || filename.isEmpty || _isSubmitting) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _error = 'Your session has expired. Please log in again.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppEnv.apiBaseUrl}/api/scanner/scan'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
        body: jsonEncode({
          if (_titleController.text.trim().isNotEmpty) 'title': _titleController.text.trim(),
          'targetType': 'pasted_snippet',
          'files': [
            {'filename': filename, 'content': code},
          ],
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['error'] as String? ?? 'The scan could not be started (${response.statusCode}).');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ScanDetailScreen(scanId: body['scanId'] as String)),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.isApiConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('New scan')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "The Security Scanner isn't configured on this build.\n\n"
              'Run with --dart-define=API_BASE_URL=... to enable it. '
              'See mobile/app/README.md.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Paste source code for a deterministic static-analysis scan -- secrets, SQL injection, XSS, '
            'command injection, and more. A rule-based engine finds these, not an AI guessing.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filenameController,
            decoration: const InputDecoration(labelText: 'Filename', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            minLines: 10,
            maxLines: 20,
            maxLength: 300000,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Run scan'),
          ),
        ],
      ),
    );
  }
}
