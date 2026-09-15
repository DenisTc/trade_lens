import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:backtest/backtest.dart';
import 'package:features_insights/src/ai/demo_transport.dart';
import 'package:features_insights/src/ai/move_summary_controller.dart';
import 'package:features_insights/src/ai/on_device_summary_provider.dart';
import 'package:features_shared/features_shared.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backtest_explanation_controller.g.dart';

/// Creates the cloud summary implementation used after on-device fallback.
@riverpod
SummaryProvider Function(ClaudeTransport transport, AiModelConfig config)
summaryProviderFactory(Ref ref) =>
    (transport, config) =>
        MetricsSummarySession(transport: transport, config: config);

@immutable
final class BacktestExplanationState {
  const BacktestExplanationState({
    this.text = '',
    this.usage = const Usage(),
    this.costUsd = 0,
    this.running = false,
    this.error,
    this.demo = false,
    this.onDevice = false,
    this.started = false,
  });

  final String text;
  final Usage usage;
  final double costUsd;
  final bool running;
  final AiError? error;
  final bool demo;
  final bool onDevice;
  // A stopped request with no text must offer retry instead of auto-starting.
  final bool started;

  bool get isIdle => !started;

  BacktestExplanationState copyWith({
    String? text,
    Usage? usage,
    double? costUsd,
    bool? running,
    AiError? error,
    bool? demo,
    bool? onDevice,
  }) => BacktestExplanationState(
    text: text ?? this.text,
    usage: usage ?? this.usage,
    costUsd: costUsd ?? this.costUsd,
    running: running ?? this.running,
    error: error,
    demo: demo ?? this.demo,
    onDevice: onDevice ?? this.onDevice,
    started: started,
  );
}

/// Owns one sheet's attempts and their total cost. No market data is fetched.
@riverpod
class BacktestExplanationController extends _$BacktestExplanationController {
  CancelSignal? _cancel;
  int _generation = 0;
  Completer<void>? _nativeSession;
  Usage _usage = const Usage();
  double _costUsd = 0;

  @override
  BacktestExplanationState build(Object key) {
    ref.onDispose(stop);
    ref.listen(aiReadinessProvider, (_, next) {
      final availability = ref.read(onDeviceAvailabilityProvider);
      final localCanStillRun =
          availability.isLoading ||
          availability.value == OnDeviceAvailability.available;
      if (next != AiReadiness.ready && !localCanStillRun && !state.demo) {
        stop();
      }
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
    final cancel = _cancel = CancelSignal();
    final generation = ++_generation;
    state = BacktestExplanationState(
      running: true,
      started: true,
      demo: demo,
      usage: _usage,
      costUsd: _costUsd,
    );
    final onDevice = !demo && await _onDeviceAvailable();
    if (!_isCurrent(generation, cancel)) return;
    if (!demo &&
        !onDevice &&
        ref.read(aiReadinessProvider) != AiReadiness.ready) {
      state = BacktestExplanationState(usage: _usage, costUsd: _costUsd);
      if (identical(_cancel, cancel)) _cancel = null;
      return;
    }
    state = state.copyWith(onDevice: onDevice);
    SummaryProvider? session;
    Completer<void>? nativeSession;
    try {
      final apiKey = demo
          ? 'demo'
          : onDevice
          ? ''
          : await ref.read(aiApiKeyProvider.future) ?? '';
      if (!_isCurrent(generation, cancel)) return;
      if (!demo && !onDevice && apiKey.isEmpty) {
        throw const AiError.unauthorized();
      }
      if (onDevice) {
        final previousNativeSession = _nativeSession;
        if (previousNativeSession != null) {
          await previousNativeSession.future;
          if (!_isCurrent(generation, cancel)) return;
        }
        nativeSession = Completer<void>();
        _nativeSession = nativeSession;
        session = OnDeviceSummaryProvider(ref.read(onDeviceLlmProvider));
      } else {
        // This shared live provider also carries the app's TL_AI_DEMO override.
        final transport = ref.read(
          demo ? demoClaudeTransportProvider : claudeTransportProvider,
        );
        state = state.copyWith(demo: demo || transport is DemoClaudeTransport);
        session = ref.read(summaryProviderFactoryProvider)(
          transport,
          ref.read(aiModelConfigProvider),
        );
      }
      await for (final event in session.explainMetrics(
        metrics: metrics,
        apiKey: apiKey,
        languageCode: languageCode,
        cancel: cancel,
      )) {
        if (!_isCurrent(generation, cancel)) return;
        if (event case SummaryText(:final delta)) {
          state = state.copyWith(text: state.text + delta);
        }
      }
    } on AiCancelled {
      // Stop and disposal keep the partial prose without an error.
    } on AiError catch (error) {
      if (_isCurrent(generation, cancel)) {
        state = state.copyWith(error: error);
      }
    } on Object catch (error) {
      if (_isCurrent(generation, cancel)) {
        state = state.copyWith(error: AiError.network('$error'));
      }
    } finally {
      if (nativeSession != null) {
        nativeSession.complete();
        if (identical(_nativeSession, nativeSession)) _nativeSession = null;
      }
      _usage += session?.usage ?? const Usage();
      _costUsd += session?.costUsd ?? 0;
      if (_isCurrent(generation, cancel)) {
        state = state.copyWith(
          running: false,
          usage: _usage,
          costUsd: _costUsd,
          error: state.error,
        );
      }
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  bool _isCurrent(int generation, CancelSignal cancel) =>
      ref.mounted && !cancel.isCancelled && generation == _generation;

  Future<bool> _onDeviceAvailable() async {
    try {
      return await ref.read(onDeviceAvailabilityProvider.future) ==
          OnDeviceAvailability.available;
    } on Object {
      return false;
    }
  }

  void stop() {
    _generation++;
    final cancel = _cancel;
    _cancel = null;
    cancel?.cancel();
    if (ref.mounted && state.running) {
      state = state.copyWith(running: false);
    }
  }
}
