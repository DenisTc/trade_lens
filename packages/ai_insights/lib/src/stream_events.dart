import 'dart:convert';

import 'package:ai_insights/src/sse.dart';
import 'package:meta/meta.dart';

/// Token counts as the API reports them; summed over a session for cost.
@immutable
final class Usage {
  const Usage({this.inputTokens = 0, this.outputTokens = 0});

  final int inputTokens;
  final int outputTokens;

  Usage operator +(Usage other) => Usage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
  );

  int get total => inputTokens + outputTokens;

  @override
  bool operator ==(Object other) =>
      other is Usage &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(inputTokens, outputTokens);

  @override
  String toString() => 'Usage(in: $inputTokens, out: $outputTokens)';
}

/// Typed view of the Messages API stream. Only what the summary needs;
/// everything else (ping, thinking blocks) becomes [StreamIgnored].
@immutable
sealed class ClaudeStreamEvent {
  const ClaudeStreamEvent();

  /// Parses one SSE event; the `type` field inside `data` is the source
  /// of truth, the SSE `event:` name is only informational.
  static ClaudeStreamEvent parse(SseEvent sse) {
    final Object? decoded;
    try {
      decoded = jsonDecode(sse.data);
    } on FormatException {
      return StreamMalformed('invalid JSON in ${sse.event}');
    }
    if (decoded is! Map<String, Object?>) {
      return const StreamMalformed('event is not an object');
    }
    switch (decoded['type']) {
      case 'message_start':
        final usage = (decoded['message'] as Map<String, Object?>?)?['usage'];
        return MessageStart(usage: _usage(usage));
      case 'content_block_start':
        final block = decoded['content_block'];
        final index = decoded['index'];
        if (block is! Map<String, Object?> || index is! int) {
          return const StreamMalformed('content_block_start without block');
        }
        return switch (block['type']) {
          'text' => BlockStart.text(index),
          'tool_use' => BlockStart.toolUse(
            index,
            id: block['id'] as String? ?? '',
            name: block['name'] as String? ?? '',
          ),
          _ => BlockStart.other(index),
        };
      case 'content_block_delta':
        final delta = decoded['delta'];
        final index = decoded['index'];
        if (delta is! Map<String, Object?> || index is! int) {
          return const StreamMalformed('content_block_delta without delta');
        }
        return switch (delta['type']) {
          'text_delta' => TextDelta(index, delta['text'] as String? ?? ''),
          'input_json_delta' => InputJsonDelta(
            index,
            delta['partial_json'] as String? ?? '',
          ),
          _ => const StreamIgnored(),
        };
      case 'content_block_stop':
        return BlockStop(decoded['index'] as int? ?? -1);
      case 'message_delta':
        final delta = decoded['delta'] as Map<String, Object?>?;
        return MessageDelta(
          stopReason: delta?['stop_reason'] as String?,
          usage: _usage(decoded['usage']),
        );
      case 'message_stop':
        return const MessageStop();
      case 'error':
        final error = decoded['error'] as Map<String, Object?>?;
        return StreamError(
          type: error?['type'] as String? ?? 'error',
          message: error?['message'] as String? ?? '',
        );
      default:
        return const StreamIgnored();
    }
  }

  static Usage _usage(Object? raw) {
    if (raw is! Map<String, Object?>) return const Usage();
    return Usage(
      inputTokens: raw['input_tokens'] as int? ?? 0,
      outputTokens: raw['output_tokens'] as int? ?? 0,
    );
  }
}

final class MessageStart extends ClaudeStreamEvent {
  const MessageStart({required this.usage});

  final Usage usage;
}

enum BlockKind { text, toolUse, other }

final class BlockStart extends ClaudeStreamEvent {
  const BlockStart._(this.index, this.kind, {this.toolId, this.toolName});

  const BlockStart.text(int index) : this._(index, BlockKind.text);

  const BlockStart.toolUse(
    int index, {
    required String id,
    required String name,
  }) : this._(index, BlockKind.toolUse, toolId: id, toolName: name);

  const BlockStart.other(int index) : this._(index, BlockKind.other);

  final int index;
  final BlockKind kind;
  final String? toolId;
  final String? toolName;
}

final class TextDelta extends ClaudeStreamEvent {
  const TextDelta(this.index, this.text);

  final int index;
  final String text;
}

final class InputJsonDelta extends ClaudeStreamEvent {
  const InputJsonDelta(this.index, this.partialJson);

  final int index;
  final String partialJson;
}

final class BlockStop extends ClaudeStreamEvent {
  const BlockStop(this.index);

  final int index;
}

final class MessageDelta extends ClaudeStreamEvent {
  const MessageDelta({required this.stopReason, required this.usage});

  final String? stopReason;
  final Usage usage;
}

final class MessageStop extends ClaudeStreamEvent {
  const MessageStop();
}

final class StreamError extends ClaudeStreamEvent {
  const StreamError({required this.type, required this.message});

  final String type;
  final String message;
}

final class StreamIgnored extends ClaudeStreamEvent {
  const StreamIgnored();
}

final class StreamMalformed extends ClaudeStreamEvent {
  const StreamMalformed(this.reason);

  final String reason;
}
