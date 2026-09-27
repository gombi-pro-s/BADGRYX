import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'modes.dart';
import 'ndjson.dart';

class _ChatMessage {
  _ChatMessage({required this.role, required this.content});

  final String role; // 'user' | 'assistant'
  String content;
}

/// AI Mentor chat, scoped to general modes only (see modes.dart) -- the
/// context-specific deep links apps/web offers from labs/investigations/
/// findings/reports aren't reachable from mobile yet, same honest scope
/// boundary as the terminal-backed labs' "not on mobile yet" banner.
///
/// Streams `/api/mentor/chat` as NDJSON via `requireApiUser()`'s Bearer-
/// token path (ADR 0033): the same route apps/web's own browser client
/// calls, just authenticated with this session's access token instead of
/// a cookie. Decoding mirrors apps/web's lib/mentor/ndjson.ts exactly --
/// see ndjson.dart.
class MentorScreen extends StatefulWidget {
  const MentorScreen({super.key});

  @override
  State<MentorScreen> createState() => _MentorScreenState();
}

class _MentorScreenState extends State<MentorScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  MentorMode _mode = MentorMode.explain;
  String? _conversationId;
  ({int used, int limit})? _quota;
  bool _isSending = false;
  String? _error;

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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _error = 'Your session has expired. Please log in again.');
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _messages.add(_ChatMessage(role: 'assistant', content: ''));
      _inputController.clear();
      _isSending = true;
      _error = null;
    });
    _scrollToBottom();

    final assistantMessage = _messages.last;

    try {
      final request = http.Request('POST', Uri.parse('${AppEnv.apiBaseUrl}/api/mentor/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${session.accessToken}'
        ..body = jsonEncode({
          'mode': _mode.apiValue,
          'message': text,
          'contextType': 'general',
          if (_conversationId != null) 'conversationId': _conversationId,
        });

      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        final parsed = _tryDecodeErrorBody(body);
        throw Exception(parsed ?? 'The Mentor request failed (${streamedResponse.statusCode}).');
      }

      var buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final result = parseNdjsonLines(buffer);
        buffer = result.remainder;
        for (final event in result.events) {
          switch (event) {
            case MentorDeltaEvent(text: final delta):
              setState(() => assistantMessage.content += delta);
              _scrollToBottom();
            case MentorDoneEvent(conversationId: final id, used: final used, limit: final limit):
              setState(() {
                _conversationId = id;
                _quota = (used: used, limit: limit);
              });
            case MentorErrorEvent(error: final message):
              throw Exception(message);
          }
        }
      }
    } catch (e) {
      setState(() {
        _messages.remove(assistantMessage);
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String? _tryDecodeErrorBody(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.isMentorConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Mentor')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "AI Mentor isn't configured on this build.\n\n"
              'Run with --dart-define=API_BASE_URL=... to enable it. '
              'See mobile/app/README.md.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final quota = _quota;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Mentor'),
        bottom: quota == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Today: ${quota.used}/${quota.limit} requests',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: MentorMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(mode.label),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                );
              }).toList(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Ask the AI Mentor to explain a concept, give a hint, or teach you something new.'),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: message.content.isEmpty && !isUser
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(message.content),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(hintText: 'Ask the Mentor...', border: OutlineInputBorder()),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _isSending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    onPressed: _isSending ? null : _send,
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
