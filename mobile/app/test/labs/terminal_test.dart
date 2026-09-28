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
}
