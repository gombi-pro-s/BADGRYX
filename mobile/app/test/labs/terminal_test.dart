import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/labs/terminal.dart';

void main() {
  group('formatTerminalPrompt', () {
    test('shows a connecting status before any prompt info is known', () {
      expect(formatTerminalPrompt(null, null, null), 'connecting...');
    });

    test('formats a real prompt once connected', () {
      expect(formatTerminalPrompt('analyst', 'workstation01', '/home/analyst'), 'analyst@workstation01:/home/analyst\$');
    });

    test('falls back to connecting if any single field is still missing', () {
      expect(formatTerminalPrompt('analyst', null, '/home/analyst'), 'connecting...');
    });
  });

  group('recallTerminalHistory', () {
    const history = ['ls', 'cat secrets.txt', 'whoami'];

    test('is a no-op with no history yet', () {
      final step = recallTerminalHistory(commandHistory: const [], historyIndex: null, direction: -1);
      expect(step.historyIndex, isNull);
      expect(step.input, isNull);
    });

    test('ArrowUp with nothing recalled yet jumps to the most recent command', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: null, direction: -1);
      expect(step.historyIndex, 2);
      expect(step.input, 'whoami');
    });

    test('repeated ArrowUp walks toward older commands', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: 2, direction: -1);
      expect(step.historyIndex, 1);
      expect(step.input, 'cat secrets.txt');
    });

    test('ArrowUp at the oldest command stays there', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: 0, direction: -1);
      expect(step.historyIndex, 0);
      expect(step.input, 'ls');
    });

    test('ArrowDown from an older command walks toward more recent ones', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: 0, direction: 1);
      expect(step.historyIndex, 1);
      expect(step.input, 'cat secrets.txt');
    });

    test('ArrowDown at the most recent command stays there', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: 2, direction: 1);
      expect(step.historyIndex, 2);
      expect(step.input, 'whoami');
    });

    test('ArrowDown while not currently browsing history clears the input', () {
      final step = recallTerminalHistory(commandHistory: history, historyIndex: null, direction: 1);
      expect(step.historyIndex, isNull);
      expect(step.input, '');
    });
  });
}
