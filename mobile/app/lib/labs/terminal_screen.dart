import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'terminal.dart';

/// A real interactive terminal, not a mockup: every command is a
/// streamed-free POST to apps/web's own /api/labs/{id}/terminal Route
/// Handler (the same one terminal.tsx calls), authenticated with the
/// Bearer-token path ADR 0033/0039 built. The entire interpreter
/// (tokenizer, virtual filesystem, multi-host ssh/exit pivoting) runs
/// server-side -- this screen is a thin request/render client, exactly
/// like terminal.tsx itself. See ADR 0040.
///
/// Command-history recall (up/down arrow) is real: the on-screen software
/// keyboard has no arrow keys, but a Bluetooth/USB keyboard or a
/// soft-keyboard app that provides them (e.g. Hacker's Keyboard) sends
/// real hardware key events either way, which a `Focus` widget around
/// the input field intercepts the exact same way terminal.tsx's own
/// `onKeyDown` does. See ADR 0050.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.labInstanceId});

  final String labInstanceId;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalEntry> _transcript = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _user;
  String? _hostname;
  String? _cwd;
  bool _pending = false;
  String? _error;
  int? _historyIndex;

  List<String> get _commandHistory => _transcript.map((e) => e.command).toList();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<Map<String, dynamic>> _callTerminal(String command) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw Exception('Your session has expired. Please log in again.');
    }
    final response = await http.post(
      Uri.parse('${AppEnv.apiBaseUrl}/api/labs/${widget.labInstanceId}/terminal'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
      body: jsonEncode({'command': command}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'The terminal is temporarily unavailable (${response.statusCode}).');
    }
    return body;
  }

  Future<void> _connect() async {
    try {
      // A silent "connect" call (empty command) to learn the real
      // cwd/user/hostname before any visible command has run -- mirrors
      // terminal.tsx's own connect effect, not logged to the transcript.
      final result = await _callTerminal('');
      setState(() {
        _user = result['user'] as String;
        _hostname = result['hostname'] as String;
        _cwd = result['cwd'] as String;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _runCommand() async {
    final command = _inputController.text.trim();
    if (command.isEmpty || _pending) return;

    if (command == 'clear') {
      setState(() {
        _transcript.clear();
        _historyIndex = null;
      });
      _inputController.clear();
      return;
    }

    setState(() {
      _pending = true;
      _error = null;
      _historyIndex = null;
    });
    _inputController.clear();

    try {
      final result = await _callTerminal(command);
      setState(() {
        _transcript.add(TerminalEntry(command: command, output: result['output'] as String));
        _user = result['user'] as String;
        _hostname = result['hostname'] as String;
        _cwd = result['cwd'] as String;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  void _recallHistory(int direction) {
    final step = recallTerminalHistory(commandHistory: _commandHistory, historyIndex: _historyIndex, direction: direction);
    if (step.input == null) return;
    setState(() {
      _historyIndex = step.historyIndex;
      _inputController.text = step.input!;
      _inputController.selection = TextSelection.collapsed(offset: step.input!.length);
    });
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _recallHistory(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _recallHistory(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.isApiConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Terminal')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "The interactive terminal isn't configured on this build.\n\n"
              'Run with --dart-define=API_BASE_URL=... to enable it. '
              'See mobile/app/README.md.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final connected = _user != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  if (_transcript.isEmpty)
                    const Text(
                      'Connected. Type a command below -- try `help` to see what\'s available.',
                      style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                    ),
                  ..._transcript.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '\$ ${entry.command}',
                            style: const TextStyle(color: Colors.lightGreenAccent, fontFamily: 'monospace', fontSize: 12),
                          ),
                          if (entry.output.isNotEmpty)
                            Text(
                              entry.output,
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_pending)
                    const Text('...', style: TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey.shade900,
              child: Row(
                children: [
                  Text(
                    formatTerminalPrompt(_user, _hostname, _cwd),
                    style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleInputKey,
                      child: TextField(
                        controller: _inputController,
                        enabled: connected && !_pending,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                        autocorrect: false,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _runCommand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
