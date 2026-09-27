import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/mentor/ndjson.dart';

void main() {
  group('parseNdjsonLines', () {
    test('parses a single complete line and leaves no remainder', () {
      final result = parseNdjsonLines('{"type":"delta","text":"hi"}\n');
      expect(result.events, [const MentorDeltaEvent('hi')]);
      expect(result.remainder, '');
    });

    test('parses multiple complete lines in one chunk', () {
      final result = parseNdjsonLines(
        '{"type":"delta","text":"a"}\n{"type":"delta","text":"b"}\n{"type":"delta","text":"c"}\n',
      );
      expect(result.events, [const MentorDeltaEvent('a'), const MentorDeltaEvent('b'), const MentorDeltaEvent('c')]);
      expect(result.remainder, '');
    });

    test('holds back an incomplete trailing line as the remainder', () {
      final result = parseNdjsonLines('{"type":"delta","text":"a"}\n{"type":"delta","te');
      expect(result.events, [const MentorDeltaEvent('a')]);
      expect(result.remainder, '{"type":"delta","te');
    });

    test('reassembles a line split across two chunks when remainder is prepended to the next chunk', () {
      final first = parseNdjsonLines('{"type":"delta","te');
      expect(first.events, isEmpty);
      expect(first.remainder, '{"type":"delta","te');

      final second = parseNdjsonLines('${first.remainder}xt":"hello"}\n');
      expect(second.events, [const MentorDeltaEvent('hello')]);
      expect(second.remainder, '');
    });

    test('skips blank lines without erroring', () {
      final result = parseNdjsonLines('{"type":"delta","text":"a"}\n\n{"type":"delta","text":"b"}\n');
      expect(result.events, [const MentorDeltaEvent('a'), const MentorDeltaEvent('b')]);
      expect(result.remainder, '');
    });

    test('parses the terminal done and error event shapes', () {
      final result = parseNdjsonLines(
        '{"type":"done","conversationId":"abc","quota":{"used":1,"limit":10,"allowed":true}}\n'
        '{"type":"error","error":"boom"}\n',
      );
      expect(result.events, [
        const MentorDoneEvent(conversationId: 'abc', used: 1, limit: 10, allowed: true),
        const MentorErrorEvent('boom'),
      ]);
    });

    test('returns no events for an empty buffer', () {
      final result = parseNdjsonLines('');
      expect(result.events, isEmpty);
      expect(result.remainder, '');
    });

    test('throws for an unknown event type', () {
      expect(() => parseNdjsonLines('{"type":"unknown"}\n'), throwsFormatException);
    });
  });
}
