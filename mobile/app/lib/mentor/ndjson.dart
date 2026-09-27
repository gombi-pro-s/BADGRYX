import 'dart:convert';

/// Mirrors apps/web's lib/mentor/ndjson.ts MentorStreamEvent union.
sealed class MentorStreamEvent {
  const MentorStreamEvent();
}

class MentorDeltaEvent extends MentorStreamEvent {
  const MentorDeltaEvent(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is MentorDeltaEvent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class MentorDoneEvent extends MentorStreamEvent {
  const MentorDoneEvent({
    required this.conversationId,
    required this.used,
    required this.limit,
    required this.allowed,
  });

  final String conversationId;
  final int used;
  final int limit;
  final bool allowed;

  @override
  bool operator ==(Object other) =>
      other is MentorDoneEvent &&
      other.conversationId == conversationId &&
      other.used == used &&
      other.limit == limit &&
      other.allowed == allowed;

  @override
  int get hashCode => Object.hash(conversationId, used, limit, allowed);
}

class MentorErrorEvent extends MentorStreamEvent {
  const MentorErrorEvent(this.error);

  final String error;

  @override
  bool operator ==(Object other) => other is MentorErrorEvent && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// Mirrors parseNdjsonLines(buffer) in apps/web's lib/mentor/ndjson.ts
/// exactly: splits on '\n', parses each complete line as one JSON event,
/// and returns any incomplete trailing text as `remainder` so the caller
/// can prepend it to the next streamed chunk -- the same chunk-boundary
/// reassembly a streamed HTTP response needs on either side.
({List<MentorStreamEvent> events, String remainder}) parseNdjsonLines(String buffer) {
  final events = <MentorStreamEvent>[];
  var rest = buffer;
  while (true) {
    final newlineIndex = rest.indexOf('\n');
    if (newlineIndex == -1) break;
    final line = rest.substring(0, newlineIndex);
    rest = rest.substring(newlineIndex + 1);
    if (line.isEmpty) continue;
    events.add(_parseEvent(jsonDecode(line) as Map<String, dynamic>));
  }
  return (events: events, remainder: rest);
}

MentorStreamEvent _parseEvent(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'delta':
      return MentorDeltaEvent(json['text'] as String);
    case 'done':
      final quota = json['quota'] as Map<String, dynamic>;
      return MentorDoneEvent(
        conversationId: json['conversationId'] as String,
        used: quota['used'] as int,
        limit: quota['limit'] as int,
        allowed: quota['allowed'] as bool,
      );
    case 'error':
      return MentorErrorEvent(json['error'] as String);
    default:
      throw FormatException('Unknown Mentor stream event type: ${json['type']}');
  }
}
