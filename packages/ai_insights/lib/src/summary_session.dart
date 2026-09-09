import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/src/errors.dart';
import 'package:ai_insights/src/model_config.dart';
import 'package:ai_insights/src/move_structure.dart';
import 'package:ai_insights/src/sse.dart';
import 'package:ai_insights/src/stream_events.dart';
import 'package:ai_insights/src/tools.dart';
import 'package:ai_insights/src/transport.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';

/// What the UI receives while a summary is produced, in order: text
/// deltas and tool calls during the loop, then the structured block (or
/// its failure), then the totals, then done. Errors end the stream.
@immutable
sealed class SummaryEvent {
  const SummaryEvent();
}

final class SummaryText extends SummaryEvent {
  const SummaryText(this.delta);

  final String delta;
}

/// The model asked for data; shown as a chip ("candles 1h · 60").
final class SummaryToolCall extends SummaryEvent {
  const SummaryToolCall(this.call);

  final ToolCall call;
}

final class SummaryStructure extends SummaryEvent {
  const SummaryStructure(this.structure);

  final MoveStructure structure;
}

/// The second call did not yield a valid block; the prose still stands.
final class SummaryStructureFailed extends SummaryEvent {
  const SummaryStructureFailed(this.reason);

  final String reason;
}

final class SummaryUsage extends SummaryEvent {
  const SummaryUsage({required this.usage, required this.costUsd});

  final Usage usage;
  final double costUsd;
}

final class SummaryDone extends SummaryEvent {
  const SummaryDone();
}

/// System prompt (spec): a market analyst describing only the data handed
/// over, no causes, no news, no advice, 5–7 sentences, the user's language.
String moveSummarySystemPrompt(String languageCode) =>
    'You are a market data analyst. You describe what the price and volume '
    'of one instrument did over roughly the last 24 hours, using only the '
    'data returned by the tools. Describe, do not explain: never invent news, '
    'events or causes, never give recommendations, forecasts or opinions '
    'about buying or selling. Write 5 to 7 plain sentences in the language '
    'with code "$languageCode". Mention the data source and the time of the '
    'newest data point. Call get_klines first; call get_orderbook once if '
    'the source has one. Do not repeat raw numbers from every candle; '
    'summarise ranges, direction and notable volume.';

/// One summary: the tool loop with streaming prose, then the structured
/// call. Pure orchestration over [ClaudeTransport]; nothing here knows
/// about Riverpod or widgets.
final class MoveSummarySession {
  MoveSummarySession({
    required ClaudeTransport transport,
    required MarketTools tools,
    required AiModelConfig config,
    Logger logger = const NoopLogger(),
    bool groundProvenance = true,
  }) : this._(
         transport,
         tools,
         ToolRunner(tools),
         config,
         logger,
         groundProvenance,
       );

  MoveSummarySession._(
    this._transport,
    this._tools,
    this._runner,
    this._config,
    this._logger,
    this._groundProvenance,
  );

  final ClaudeTransport _transport;
  final ToolRunner _runner;
  final MarketTools _tools;
  final AiModelConfig _config;
  final Logger _logger;

  /// Replaces the source the model wrote with the one the data actually
  /// came from, so attribution cannot be a guess. Off when replaying a
  /// recorded example, whose numbers are not from the live source.
  final bool _groundProvenance;

  Usage _usage = const Usage();

  /// Tokens billed so far in this session, across every call. Readable
  /// after a failure too: those calls were charged even though no answer
  /// reached the screen.
  Usage get usage => _usage;

  double get costUsd => _config.costUsd(
    inputTokens: _usage.inputTokens,
    outputTokens: _usage.outputTokens,
  );

  /// Streams the summary of [instrument]. Cancel through [cancel]; the
  /// stream then ends with [AiCancelled].
  Stream<SummaryEvent> run({
    required Instrument instrument,
    required String apiKey,
    required String languageCode,
    required CancelSignal cancel,
  }) async* {
    final tools = ToolSchemas.definitions(
      symbols: _tools.instruments.map((i) => i.symbol),
      intervals: _tools.intervals.map((i) => i.code),
    );
    final messages = <Map<String, Object?>>[
      {
        'role': 'user',
        'content':
            'Summarise the recent move of ${instrument.symbol} '
            '(${instrument.base.name} against ${instrument.quote}). '
            'The data comes from ${_tools.sourceName}; name that source in '
            'the answer.',
      },
    ];
    final prose = StringBuffer();

    var toolRounds = 0;
    while (true) {
      // Refuse to spend more before the call, not after it.
      _checkBudget();
      final turn = _Turn();
      await for (final event in _stream(
        {
          'model': _config.model,
          'max_tokens': _maxOutput(_config.maxOutputTokens),
          'stream': true,
          'system': moveSummarySystemPrompt(languageCode),
          'tools': tools,
          'messages': List<Map<String, Object?>>.of(messages),
        },
        apiKey: apiKey,
        cancel: cancel,
        turn: turn,
      )) {
        if (event is SummaryText) prose.write(event.delta);
        yield event;
      }
      _checkBudget();
      messages.add({'role': 'assistant', 'content': turn.assistantContent()});
      if (turn.stopReason == 'refusal') throw const AiError.refused();
      if (turn.toolCalls.isEmpty || turn.stopReason != 'tool_use') break;
      if (toolRounds >= _config.maxToolIterations) {
        throw AiError.budgetExceeded(
          'more than ${_config.maxToolIterations} tool iterations',
        );
      }
      toolRounds++;
      final results = <Map<String, Object?>>[];
      for (final call in turn.toolCalls) {
        if (cancel.isCancelled) throw const AiError.cancelled();
        yield SummaryToolCall(call);
        results.add({
          'type': 'tool_result',
          'tool_use_id': call.id,
          'content': await _runner.run(call),
        });
      }
      messages.add({'role': 'user', 'content': results});
    }

    if (prose.isEmpty) {
      throw const AiError.invalidResponse('the model returned no text');
    }

    // Second call: the structured block from the prose, no tools.
    final structured = _Turn();
    try {
      _checkBudget();
      await for (final _ in _stream(
        {
          'model': _config.model,
          'max_tokens': _maxOutput(400),
          'stream': true,
          'system':
              'Extract the structured summary from the analysis. Use only '
              'facts stated in it. dataAsOf is the time of the newest data '
              'point mentioned, ISO-8601 UTC.',
          'messages': [
            {'role': 'user', 'content': prose.toString()},
          ],
          'output_config': {
            'format': {'type': 'json_schema', 'schema': MoveStructure.schema},
          },
        },
        apiKey: apiKey,
        cancel: cancel,
        turn: structured,
      )) {}
      _checkBudget();
      switch (MoveStructure.parse(structured.text.toString())) {
        case Ok(:final value):
          yield SummaryStructure(
            _groundProvenance ? value.withSource(_tools.sourceName) : value,
          );
        case Err(:final error):
          _logger.warn('structured output rejected: $error');
          yield SummaryStructureFailed(error);
      }
    } on AiCancelled {
      rethrow;
    } on AiError catch (e) {
      // The prose is already on screen; the block is optional.
      _logger.warn('structured call failed', e);
      yield SummaryStructureFailed('$e');
    }

    yield SummaryUsage(usage: _usage, costUsd: costUsd);
    yield const SummaryDone();
  }

  /// Tokens left before the session budget is spent.
  int get _remainingTokens => _config.maxSessionTokens - _usage.total;

  void _checkBudget() {
    if (_remainingTokens <= 0) {
      throw AiError.budgetExceeded(
        '${_usage.total} tokens of the ${_config.maxSessionTokens} budget',
      );
    }
  }

  /// Output allowance for the next call, never more than the budget left.
  int _maxOutput(int wanted) =>
      wanted < _remainingTokens ? wanted : _remainingTokens;

  /// One request: sends [body], yields text deltas, fills [turn].
  Stream<SummaryEvent> _stream(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
    required _Turn turn,
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
          case MessageStart(:final usage):
            _usage += Usage(inputTokens: usage.inputTokens);
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
              yield SummaryText(text);
            }
          case InputJsonDelta(:final index, :final partialJson):
            turn.appendJson(index, partialJson);
          case BlockStop(:final index):
            turn.stopBlock(index);
          case MessageDelta(:final stopReason, :final usage):
            turn.stopReason = stopReason ?? turn.stopReason;
            if (usage.outputTokens > countedOutput) {
              _usage += Usage(outputTokens: usage.outputTokens - countedOutput);
              countedOutput = usage.outputTokens;
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
final class _Turn {
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
