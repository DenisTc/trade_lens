import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:flutter/services.dart';
import 'package:on_device_llm/on_device_llm.dart';

/// Adapts the native completed-answer API to [SummaryProvider].
///
/// Native runtimes do not stream yet, so one complete [SummaryText] event is
/// emitted without an artificial typing delay, followed by zero usage and done.
final class OnDeviceSummaryProvider implements SummaryProvider {
  OnDeviceSummaryProvider(this._llm);

  final OnDeviceLlmApi _llm;

  @override
  Usage get usage => const Usage();

  @override
  double get costUsd => 0;

  @override
  Stream<SummaryEvent> explainMetrics({
    required Map<String, Object?> metrics,
    required String apiKey,
    required String languageCode,
    required CancelSignal cancel,
  }) async* {
    Future<void>? cancellationRequest;
    Future<void> cancelNative() => cancellationRequest ??= _llm.cancel();

    if (cancel.isCancelled) {
      await cancelNative();
      throw const AiError.cancelled();
    }

    final generation = _llm.generate(
      system: metricsSummarySystemPrompt(languageCode),
      prompt: metricsSummaryUserPrompt(metrics),
      languageCode: languageCode,
      maxOutputChars: 2000,
    );
    Future<void> awaitGenerationSettlement() async {
      try {
        await generation;
      } on Object {
        // Cancellation commonly completes generation with a native error.
      }
    }

    final cancellation = cancel.whenCancelled.then<String>((_) async {
      await cancelNative();
      await awaitGenerationSettlement();
      throw const AiError.cancelled();
    });

    try {
      final text = await Future.any<String>([generation, cancellation]);
      if (cancel.isCancelled) {
        await cancelNative();
        await awaitGenerationSettlement();
        throw const AiError.cancelled();
      }
      if (text.trim().isEmpty) {
        throw const AiError.invalidResponse('the model returned no text');
      }
      yield SummaryText(text);
      yield const SummaryUsage(usage: Usage(), costUsd: 0);
      yield const SummaryDone();
    } on AiError {
      rethrow;
    } on Object catch (error) {
      if (cancel.isCancelled) {
        await cancelNative();
        await awaitGenerationSettlement();
        throw const AiError.cancelled();
      }
      final reason = switch (error) {
        PlatformException(:final message, :final code) => message ?? code,
        _ => '$error',
      };
      throw AiError.onDevice(reason);
    }
  }
}
