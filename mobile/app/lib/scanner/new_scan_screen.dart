import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'scan.dart';
import 'scan_detail_screen.dart';

/// Either a pasted single-file snippet, or real multi-file upload (up to
/// the same 20-file limit `/api/scanner/scan`'s own requestSchema already
/// enforces) -- `targetType` follows whichever the user actually used,
/// via `buildScanRequestBody()`. Submits via the same requireApiUser()
/// Bearer-token path ADR 0033/0035 built for /api/scanner/scan. See
/// ADR 0048.
class NewScanScreen extends StatefulWidget {
  const NewScanScreen({super.key});

  @override
  State<NewScanScreen> createState() => _NewScanScreenState();
}

class _NewScanScreenState extends State<NewScanScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController(text: 'snippet.js');
  List<ScanUploadFile> _pickedFiles = [];
  bool _isSubmitting = false;
  bool _isPicking = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
      if (result == null) return;
      final files = result.files.map((f) {
        final bytes = f.bytes;
        if (bytes == null) throw Exception('Could not read ${f.name}.');
        return ScanUploadFile(filename: f.name, content: utf8.decode(bytes, allowMalformed: true));
      }).toList();
      setState(() => _pickedFiles = files);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removePickedFile(int index) {
    setState(() => _pickedFiles = [..._pickedFiles]..removeAt(index));
  }

  Future<void> _submit() async {
    final usingPickedFiles = _pickedFiles.isNotEmpty;
    final code = _codeController.text.trim();
    final filename = _filenameController.text.trim();
    if (!usingPickedFiles && (code.isEmpty || filename.isEmpty)) {
      setState(() => _error = 'Paste some code, or pick one or more files to upload.');
      return;
    }
    if (_isSubmitting) return;

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
        body: jsonEncode(
          buildScanRequestBody(
            title: _titleController.text.trim(),
            pickedFiles: _pickedFiles,
            pastedFilename: filename,
            pastedCode: code,
          ),
        ),
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
            'Paste source code, or pick one or more real files, for a deterministic static-analysis scan -- '
            'secrets, SQL injection, XSS, command injection, and more. A rule-based engine finds these, not an '
            'AI guessing.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_isPicking ? 'Choosing...' : 'Choose files'),
            onPressed: _isPicking ? null : _pickFiles,
          ),
          if (_pickedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...List.generate(_pickedFiles.length, (index) {
              final file = _pickedFiles[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(file.filename),
                  subtitle: Text('${file.content.length} characters'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removePickedFile(index),
                  ),
                ),
              );
            }),
          ],
          if (_pickedFiles.isEmpty) ...[
            const SizedBox(height: 16),
            Text('Or paste a single snippet:', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
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
          ],
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
