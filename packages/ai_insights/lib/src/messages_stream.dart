import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/src/errors.dart';
import 'package:ai_insights/src/sse.dart';
import 'package:ai_insights/src/stream_events.dart';
import 'package:ai_insights/src/tools.dart';
import 'package:ai_insights/src/transport.dart';

/// Shared Messages SSE decoding, cancellation, HTTP errors and billing.
final class MessagesStream {
  MessagesStream(this._transport);

  final ClaudeTransport _transport;
  Usage usage = const Usage();

  /// One request: sends [body], yields text deltas, fills [turn].
  Stream<String> stream(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
    required MessageTurn turn,
  }) async* {
    if (cancel.isCancelled) throw const AiError.cancelled();
    final ClaudeResponse response;
    try {
      response = await _transport.post(body, apiKey: apiKey, cancel: cancel);
    } on AiError {
      rethrow;
    } on Object catch (e) {
      throw AiError.network('$e');
    }
    if (response.status != 200) {
      throw await _errorFor(response);
    }
    // A stream iterator rather than `await for`: each step races the
    // cancel signal, so a silent stream (a stalled connection, a transport
    // that ignores cancellation) still stops when the user leaves.
    final events = StreamIterator(
      response.body.transform(const SseDecoder()).map(ClaudeStreamEvent.parse),
    );
    var sawStop = false;
    // `message_delta.usage.output_tokens` is the running total for this
    // message, not an increment: only the growth is billed once.
    var countedOutput = 0;
    // One continuation for the whole stream, not one per event.
    final cancelled = cancel.whenCancelled.then((_) => false);
    var drained = false;
    try {
      while (true) {
        final hasEvent = await Future.any([events.moveNext(), cancelled]);
        if (cancel.isCancelled) throw const AiError.cancelled();
        if (!hasEvent) {
          drained = true;
          break;
        }
        final event = events.current;
        switch (event) {
          case MessageStart(usage: final messageUsage):
            usage += Usage(inputTokens: messageUsage.inputTokens);
          case BlockStart(
            :final index,
            :final kind,
            :final toolId,
            :final toolName,
          ):
            turn.startBlock(index, kind, toolId, toolName);
          case TextDelta(:final index, :final text):
            if (turn.isText(index)) {
              turn.text.write(text);
              yield text;
            }
          case InputJsonDelta(:final index, :final partialJson):
            turn.appendJson(index, partialJson);
          case BlockStop(:final index):
            turn.stopBlock(index);
          case MessageDelta(:final stopReason, usage: final messageUsage):
            turn.stopReason = stopReason ?? turn.stopReason;
            if (messageUsage.outputTokens > countedOutput) {
              usage += Usage(
                outputTokens: messageUsage.outputTokens - countedOutput,
              );
              countedOutput = messageUsage.outputTokens;
            }
          case MessageStop():
            sawStop = true;
          case StreamError(:final type, :final message):
            throw type == 'overloaded_error'
                ? const AiError.rateLimited()
                : AiError.invalidResponse('$type: $message');
          case StreamMalformed(:final reason):
            throw AiError.invalidResponse(reason);
          case StreamIgnored():
            break;
        }
      }
    } finally {
      // Never awaited: cancelling a subscription whose source is stalled
      // can hang until the socket closes, and the caller is already gone.
      if (!drained) unawaited(events.cancel());
    }
    if (cancel.isCancelled) throw const AiError.cancelled();
    if (!sawStop) {
      throw const AiError.invalidResponse('stream ended before message_stop');
    }
    if (turn.stopReason == 'max_tokens') {
      throw const AiError.budgetExceeded('max_tokens reached');
    }
  }

  Future<AiError> _errorFor(ClaudeResponse response) async {
    String? message;
    try {
      final text = await utf8.decodeStream(response.body);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        message =
            (decoded['error'] as Map<String, Object?>?)?['message'] as String?;
      }
    } on Object {
      message = null;
    }
    final retry = response.headers['retry-after'];
    final seconds = retry == null ? null : int.tryParse(retry);
    return aiErrorForStatus(
      response.status,
      message: message,
      retryAfter: seconds == null ? null : Duration(seconds: seconds),
    );
  }
}

/// Accumulates one assistant turn from stream events.
final class MessageTurn {
  final text = StringBuffer();
  final _blocks = <int, _Block>{};
  final toolCalls = <ToolCall>[];
  String? stopReason;

  void startBlock(int index, BlockKind kind, String? id, String? name) =>
      _blocks[index] = _Block(kind, id ?? '', name ?? '');

  bool isText(int index) => _blocks[index]?.kind == BlockKind.text;

  void appendJson(int index, String partial) =>
      _blocks[index]?.json.write(partial);

  void stopBlock(int index) {
    final block = _blocks[index];
    if (block == null || block.kind != BlockKind.toolUse) return;
    final raw = block.json.isEmpty ? '{}' : block.json.toString();
    Map<String, Object?> input;
    try {
      final decoded = jsonDecode(raw);
      input = decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      input = {};
    }
    toolCalls.add(ToolCall(id: block.id, name: block.name, input: input));
    block.input = input;
  }

  /// The assistant message to echo back, tool_use blocks included, so the
  /// next request carries the full turn (spec: tool loop).
  List<Map<String, Object?>> assistantContent() {
    final content = <Map<String, Object?>>[];
    if (text.isNotEmpty) content.add({'type': 'text', 'text': text.toString()});
    for (final call in toolCalls) {
      content.add({
        'type': 'tool_use',
        'id': call.id,
        'name': call.name,
        'input': call.input,
      });
    }
    if (content.isEmpty) content.add({'type': 'text', 'text': '…'});
    return content;
  }
}

final class _Block {
  _Block(this.kind, this.id, this.name);

  final BlockKind kind;
  final String id;
  final String name;
  final json = StringBuffer();
  Map<String, Object?> input = const {};
}
