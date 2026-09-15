import 'package:ai_insights/ai_insights.dart';
import 'package:backtest/backtest.dart';
import 'package:features_insights/src/ai/move_summary_controller.dart';
import 'package:features_shared/features_shared.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backtest_explanation_controller.g.dart';

@immutable
final class BacktestExplanationState {
  const BacktestExplanationState({
    this.text = '',
    this.usage = const Usage(),
    this.costUsd = 0,
    this.running = false,
    this.error,
    this.demo = false,
    this.started = false,
  });

  final String text;
  final Usage usage;
  final double costUsd;
  final bool running;
  final AiError? error;
  final bool demo;
  // A stopped request with no text must offer retry instead of auto-starting.
  final bool started;

  bool get isIdle => !started;

  BacktestExplanationState copyWith({
    String? text,
    Usage? usage,
    double? costUsd,
    bool? running,
    AiError? error,
  }) => BacktestExplanationState(
    text: text ?? this.text,
    usage: usage ?? this.usage,
    costUsd: costUsd ?? this.costUsd,
    running: running ?? this.running,
    error: error,
    demo: demo,
    started: started,
  );
}

/// Owns one sheet's attempts and their total cost. No market data is fetched.
@riverpod
class BacktestExplanationController extends _$BacktestExplanationController {
  CancelSignal? _cancel;
  Usage _usage = const Usage();
  double _costUsd = 0;

  @override
  BacktestExplanationState build(String key) {
    ref.onDispose(stop);
    ref.listen(aiReadinessProvider, (_, next) {
      if (next != AiReadiness.ready && !state.demo) stop();
    });
    return const BacktestExplanationState();
  }

  Future<void> start({
    required BacktestMetrics metrics,
    String languageCode = 'en',
  }) =>
      _run(metrics: metrics.toJson(), languageCode: languageCode, demo: false);

  Future<void> showExample({String languageCode = 'en'}) =>
      _run(metrics: const {}, languageCode: languageCode, demo: true);

  Future<void> _run({
    required Map<String, Object?> metrics,
    required String languageCode,
    required bool demo,
  }) async {
    if (state.running) return;
    if (!demo && ref.read(aiReadinessProvider) != AiReadiness.ready) {
      state = BacktestExplanationState(usage: _usage, costUsd: _costUsd);
      return;
    }
    final cancel = _cancel = CancelSignal();
    state = BacktestExplanationState(
      running: true,
      started: true,
      demo: demo,
      usage: _usage,
      costUsd: _costUsd,
    );
    SummaryProvider? session;
    try {
      final apiKey = demo
          ? 'demo'
          : await ref.read(aiApiKeyProvider.future) ?? '';
      if (cancel.isCancelled || !ref.mounted) return;
      if (!demo && apiKey.isEmpty) throw const AiError.unauthorized();
      // This shared live provider also carries the app's TL_AI_DEMO override.
      session = MetricsSummarySession(
        transport: ref.read(
          demo ? demoClaudeTransportProvider : claudeTransportProvider,
        ),
        config: ref.read(aiModelConfigProvider),
      );
      await for (final event in session.explainMetrics(
        metrics: metrics,
        apiKey: apiKey,
        languageCode: languageCode,
        cancel: cancel,
      )) {
        if (cancel.isCancelled || !ref.mounted) return;
        if (event case SummaryText(:final delta)) {
          state = state.copyWith(text: state.text + delta);
        }
      }
    } on AiCancelled {
      // Stop and disposal keep the partial prose without an error.
    } on AiError catch (error) {
      if (ref.mounted && !cancel.isCancelled) {
        state = state.copyWith(error: error);
      }
    } on Object catch (error) {
      if (ref.mounted && !cancel.isCancelled) {
        state = state.copyWith(error: AiError.network('$error'));
      }
    } finally {
      _usage += session?.usage ?? const Usage();
      _costUsd += session?.costUsd ?? 0;
      if (ref.mounted) {
        state = state.copyWith(
          running: false,
          usage: _usage,
          costUsd: _costUsd,
          error: state.error,
        );
      }
      _cancel = null;
    }
  }

  void stop() => _cancel?.cancel();
}
