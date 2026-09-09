import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/src/ai/demo_transport.dart';
import 'package:features_insights/src/ai/market_tools_adapter.dart';
import 'package:features_shared/features_shared.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'move_summary_controller.g.dart';

/// Live transport to the Claude API. Declared here without an
/// implementation; the app overrides it with the Dio + pinning one.
@Riverpod(keepAlive: true)
ClaudeTransport claudeTransport(Ref ref) =>
    throw UnimplementedError('claudeTransportProvider must be overridden');

/// Replays the bundled example instead of calling the API. Overridable so
/// tests and screenshots can drop the typing delay.
@Riverpod(keepAlive: true)
ClaudeTransport demoClaudeTransport(Ref ref) => DemoClaudeTransport();

/// Model id, prices and limits from Remote Config (`ai_model`), bundled
/// defaults until it arrives.
@riverpod
AiModelConfig aiModelConfig(Ref ref) =>
    AiModelConfig.parse(ref.watch(insightsConfigProvider).value?.aiModelJson);

/// What the sheet renders. `demo` marks the recorded example; [usage] and
/// [costUsd] are the totals of every call made for this pair, including
/// attempts that ended in an error, because those were billed too.
@immutable
final class MoveSummaryState {
  const MoveSummaryState({
    this.text = '',
    this.toolCalls = const [],
    this.structure,
    this.structureError,
    this.usage = const Usage(),
    this.costUsd = 0,
    this.running = false,
    this.error,
    this.demo = false,
  });

  final String text;
  final List<ToolCall> toolCalls;
  final MoveStructure? structure;

  /// The structured block was rejected; the prose above still stands.
  final String? structureError;
  final Usage usage;
  final double costUsd;
  final bool running;
  final AiError? error;
  final bool demo;

  bool get isIdle => !running && text.isEmpty && error == null;

  MoveSummaryState copyWith({
    String? text,
    List<ToolCall>? toolCalls,
    MoveStructure? structure,
    String? structureError,
    Usage? usage,
    double? costUsd,
    bool? running,
    AiError? error,
    bool? demo,
  }) => MoveSummaryState(
    text: text ?? this.text,
    toolCalls: toolCalls ?? this.toolCalls,
    structure: structure ?? this.structure,
    structureError: structureError ?? this.structureError,
    usage: usage ?? this.usage,
    costUsd: costUsd ?? this.costUsd,
    running: running ?? this.running,
    error: error,
    demo: demo ?? this.demo,
  );
}

/// Runs summaries for one instrument and streams them into the sheet.
/// Leaving the screen disposes the provider, which cancels the request
/// (spec: cancellation on leaving), and losing consent or the remote flag
/// mid-stream cancels it as well.
@riverpod
class MoveSummaryController extends _$MoveSummaryController {
  CancelSignal? _cancel;
  int _attempt = 0;
  Usage _sessionUsage = const Usage();
  double _sessionCost = 0;

  @override
  MoveSummaryState build(Instrument instrument) {
    ref.onDispose(cancel);
    ref.listen(aiReadinessProvider, (_, next) {
      if (next != AiReadiness.ready && state.running && !state.demo) cancel();
    });
    return const MoveSummaryState();
  }

  /// Starts a run. [demo] replays the bundled example and needs no key,
  /// no consent and no flag.
  Future<void> start({bool demo = false, String languageCode = 'en'}) async {
    if (state.running) return;
    if (!demo && ref.read(aiReadinessProvider) != AiReadiness.ready) {
      // Back to the gate, which names what is missing.
      state = MoveSummaryState(usage: _sessionUsage, costUsd: _sessionCost);
      return;
    }
    final cancel = _cancel = CancelSignal();
    final attempt = ++_attempt;
    state = MoveSummaryState(
      running: true,
      demo: demo,
      usage: _sessionUsage,
      costUsd: _sessionCost,
    );
    MoveSummarySession? session;
    try {
      final apiKey = demo
          ? 'demo'
          : await ref.read(aiApiKeyProvider.future) ?? '';
      if (!demo && apiKey.isEmpty) throw const AiError.unauthorized();
      final source = await ref.read(marketDataSourceProvider.future);
      session = MoveSummarySession(
        transport: ref.read(
          demo ? demoClaudeTransportProvider : claudeTransportProvider,
        ),
        tools: RiverpodMarketTools(
          ref: ref,
          source: source,
          instrument: instrument,
        ),
        config: ref.read(aiModelConfigProvider),
        // The recorded example's numbers are not from the live source.
        groundProvenance: !demo,
      );
      await for (final event in session.run(
        instrument: instrument,
        apiKey: apiKey,
        languageCode: languageCode,
        cancel: cancel,
      )) {
        if (cancel.isCancelled || !ref.mounted || attempt != _attempt) return;
        state = switch (event) {
          SummaryText(:final delta) => state.copyWith(text: state.text + delta),
          SummaryToolCall(:final call) => state.copyWith(
            toolCalls: [...state.toolCalls, call],
          ),
          SummaryStructure(:final structure) => state.copyWith(
            structure: structure,
          ),
          SummaryStructureFailed(:final reason) => state.copyWith(
            structureError: reason,
          ),
          // Totals are folded in below, from the session itself, so a run
          // that fails halfway still reports what it spent.
          SummaryUsage() || SummaryDone() => state,
        };
      }
    } on AiCancelled {
      // Nothing to report: the user left or stopped it.
    } on AiError catch (e) {
      if (ref.mounted && attempt == _attempt) state = state.copyWith(error: e);
    } on Object catch (e) {
      if (ref.mounted && attempt == _attempt) {
        state = state.copyWith(error: AiError.network('$e'));
      }
    } finally {
      // The charges are real whoever started them, so they are always
      // folded in; only the visible state belongs to the newest attempt.
      _sessionUsage += session?.usage ?? const Usage();
      _sessionCost += session?.costUsd ?? 0;
      if (ref.mounted && attempt == _attempt) {
        state = state.copyWith(
          running: false,
          usage: _sessionUsage,
          costUsd: _sessionCost,
          error: state.error,
        );
      }
    }
  }

  /// Clears the previous answer and runs again, keeping what the earlier
  /// attempts already cost.
  Future<void> retry({bool demo = false, String languageCode = 'en'}) async {
    cancel();
    state = MoveSummaryState(usage: _sessionUsage, costUsd: _sessionCost);
    await start(demo: demo, languageCode: languageCode);
  }

  void cancel() {
    _cancel?.cancel();
    _cancel = null;
  }
}
