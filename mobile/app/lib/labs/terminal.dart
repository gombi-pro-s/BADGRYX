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

/// The result of one recallHistory() step: `input == null` means "leave
/// the input box alone" (only the empty-history no-op case below).
class TerminalHistoryStep {
  TerminalHistoryStep({required this.historyIndex, required this.input});

  final int? historyIndex;
  final String? input;
}

/// Mirrors apps/web's terminal.tsx recallHistory() exactly, including its
/// one real quirk: pressing ArrowDown while not currently browsing history
/// (`historyIndex == null`) clears the input rather than being a no-op --
/// this is a faithful port of existing behavior, not a new design.
/// `direction` is -1 for ArrowUp (older), +1 for ArrowDown (newer).
TerminalHistoryStep recallTerminalHistory({
  required List<String> commandHistory,
  required int? historyIndex,
  required int direction,
}) {
  if (commandHistory.isEmpty) return TerminalHistoryStep(historyIndex: historyIndex, input: null);
  final int? nextIndex = historyIndex == null
      ? (direction == -1 ? commandHistory.length - 1 : null)
      : (historyIndex + direction).clamp(0, commandHistory.length - 1);
  if (nextIndex == null) {
    return TerminalHistoryStep(historyIndex: null, input: '');
  }
  return TerminalHistoryStep(historyIndex: nextIndex, input: commandHistory[nextIndex]);
}
