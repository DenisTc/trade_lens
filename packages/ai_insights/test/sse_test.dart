import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:test/test.dart';

void main() {
  const raw =
      'event: message_start\n'
      'data: {"type":"message_start","message":{"usage":{"input_tokens":12,"output_tokens":1}}}\n'
      '\n'
      ': keep-alive comment\n'
      'event: content_block_delta\n'
      'data: {"type":"content_block_delta","index":0,\n'
      'data: "delta":{"type":"text_delta","text":"Привет"}}\n'
      '\n'
      'event: message_stop\n'
      'data: {"type":"message_stop"}\n'
      '\n';

  Future<List<SseEvent>> decode(List<List<int>> chunks) =>
      Stream.fromIterable(chunks).transform(const SseDecoder()).toList();

  test('assembles events from one chunk and joins multi-line data', () async {
    final events = await decode([utf8.encode(raw)]);
    expect(events.map((e) => e.event), [
      'message_start',
      'content_block_delta',
      'message_stop',
    ]);
    expect(events[1].data, contains('"delta":{"type":"text_delta"'));
    expect(events[1].data, contains('\n'));
  });

  test(
    'is chunk-boundary agnostic, including inside UTF-8 sequences',
    () async {
      final bytes = utf8.encode(raw);
      for (final size in [1, 2, 3, 7, 64]) {
        final chunks = [
          for (var i = 0; i < bytes.length; i += size)
            bytes.sublist(i, (i + size).clamp(0, bytes.length)),
        ];
        final events = await decode(chunks);
        expect(events, hasLength(3), reason: 'chunk size $size');
        final parsed = ClaudeStreamEvent.parse(events[1]);
        expect(
          (parsed as TextDelta).text,
          'Привет',
          reason: 'chunk size $size',
        );
      }
    },
  );

  test('a trailing event without a blank line is still delivered', () async {
    final events = await decode([
      utf8.encode('event: message_stop\ndata: {"type":"message_stop"}'),
    ]);
    expect(events, hasLength(1));
  });

  test('typed parsing covers the events the session needs', () {
    ClaudeStreamEvent parse(Map<String, Object?> e) =>
        ClaudeStreamEvent.parse(SseEvent(event: '', data: jsonEncode(e)));

    expect(
      (parse({
        'type': 'message_start',
        'message': {
          'usage': {'input_tokens': 5},
        },
      }) as MessageStart).usage.inputTokens,
      5,
    );
    final start = parse({
      'type': 'content_block_start',
      'index': 1,
      'content_block': {'type': 'tool_use', 'id': 't1', 'name': 'x'},
    }) as BlockStart;
    expect(start.kind, BlockKind.toolUse);
    expect(start.toolId, 't1');
    expect(
      (parse({
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"a'},
      }) as InputJsonDelta).partialJson,
      '{"a',
    );
    final delta = parse({
      'type': 'message_delta',
      'delta': {'stop_reason': 'tool_use'},
      'usage': {'output_tokens': 9},
    }) as MessageDelta;
    expect(delta.stopReason, 'tool_use');
    expect(delta.usage.outputTokens, 9);
    expect(
      parse({
        'type': 'error',
        'error': {'type': 'overloaded_error', 'message': 'x'},
      }),
      isA<StreamError>(),
    );
    expect(parse({'type': 'ping'}), isA<StreamIgnored>());
    expect(
      ClaudeStreamEvent.parse(const SseEvent(event: 'x', data: '{')),
      isA<StreamMalformed>(),
    );
  });
}
