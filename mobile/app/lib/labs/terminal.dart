class TerminalEntry {
  TerminalEntry({required this.command, required this.output});

  final String command;
  final String output;
}

/// Mirrors apps/web's terminal.tsx promptString() exactly: no prompt info
/// yet (still connecting) shows a plain status instead of a bare "null"
/// prompt.
String formatTerminalPrompt(String? user, String? hostname, String? cwd) {
  if (user == null || hostname == null || cwd == null) return 'connecting...';
  return '$user@$hostname:$cwd\$';
}
