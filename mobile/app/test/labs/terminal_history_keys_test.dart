import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/labs/terminal.dart';

/// Proves the actual wiring terminal_screen.dart uses -- a `Focus` widget
/// wrapping the input `TextField` -- really does intercept a hardware
/// ArrowUp/ArrowDown key event before `TextField`'s own default text-
/// editing shortcuts (declared near the widget tree's root, so this
/// closer-to-the-leaf `Focus` sees the event first) can consume it. This
/// is the one part of ADR 0050 that isn't just the pure recallTerminalHistory()
/// logic -- it depends on Flutter's focus-dispatch order, so it gets an
/// actual key-event simulation rather than being taken on faith.
class _HistoryHarness extends StatefulWidget {
  const _HistoryHarness({required this.commandHistory});

  final List<String> commandHistory;

  @override
  State<_HistoryHarness> createState() => _HistoryHarnessState();
}

class _HistoryHarnessState extends State<_HistoryHarness> {
  final _controller = TextEditingController();
  int? _historyIndex;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    int direction;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      direction = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      direction = 1;
    } else {
      return KeyEventResult.ignored;
    }
    final step = recallTerminalHistory(
      commandHistory: widget.commandHistory,
      historyIndex: _historyIndex,
      direction: direction,
    );
    if (step.input == null) return KeyEventResult.ignored;
    setState(() {
      _historyIndex = step.historyIndex;
      _controller.text = step.input!;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Focus(onKeyEvent: _handleKey, child: TextField(controller: _controller, autofocus: true)),
      ),
    );
  }
}

void main() {
  testWidgets('a real ArrowUp key event recalls the most recent command into the field', (tester) async {
    await tester.pumpWidget(const _HistoryHarness(commandHistory: ['ls', 'whoami']));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(find.text('whoami'), findsOneWidget);
  });

  testWidgets('repeated real ArrowUp events walk back through older commands', (tester) async {
    await tester.pumpWidget(const _HistoryHarness(commandHistory: ['ls', 'cat secrets.txt', 'whoami']));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(find.text('cat secrets.txt'), findsOneWidget);
  });

  testWidgets('a real ArrowDown event after ArrowUp walks forward again', (tester) async {
    await tester.pumpWidget(const _HistoryHarness(commandHistory: ['ls', 'cat secrets.txt', 'whoami']));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.text('whoami'), findsOneWidget);
  });

  testWidgets('typing normally still works once the Focus wrapper is in place', (tester) async {
    await tester.pumpWidget(const _HistoryHarness(commandHistory: []));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'help');
    await tester.pump();

    expect(find.text('help'), findsOneWidget);
  });
}
