import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:features_insights/src/ai/on_device_summary_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_device_llm/on_device_llm.dart';

void main() {
  late _FakeOnDeviceLlm llm;
  late OnDeviceSummaryProvider provider;

  setUp(() {
    llm = _FakeOnDeviceLlm();
    provider = OnDeviceSummaryProvider(llm);
  });

  test('emits the completed local answer with zero token usage', () async {
    llm.answer = 'Локальное объяснение результата.';

    final events = await provider
        .explainMetrics(
          metrics: const {'symbol': 'BTCUSDT', 'profitPct': '5'},
          apiKey: '',
          languageCode: 'ru',
          cancel: CancelSignal(),
        )
        .toList();

    expect(llm.system, metricsSummarySystemPrompt('ru'));
    expect(
      llm.prompt,
      'Explain these computed backtest metrics.\n'
      '```json\n{"symbol":"BTCUSDT","profitPct":"5"}\n```',
    );
    expect(llm.languageCode, 'ru');
    expect(llm.maxOutputChars, 2000);
    expect(events, hasLength(3));
    expect(
      (events[0] as SummaryText).delta,
      'Локальное объяснение результата.',
    );
    expect((events[1] as SummaryUsage).usage, const Usage());
    expect((events[1] as SummaryUsage).costUsd, 0);
    expect(events[2], isA<SummaryDone>());
    expect(provider.usage, const Usage());
    expect(provider.costUsd, 0);
  });

  test(
    'cancellation reaches native generation and ends with AiCancelled',
    () async {
      llm.pending = Completer<String>();
      final cancel = CancelSignal();
      final events = provider
          .explainMetrics(
            metrics: const {'symbol': 'ETHUSDT'},
            apiKey: '',
            languageCode: 'en',
            cancel: cancel,
          )
          .toList();
      await Future<void>.delayed(Duration.zero);

      cancel.cancel();

      await expectLater(events, throwsA(isA<AiCancelled>()));
      expect(llm.cancelled, isTrue);
    },
  );

  test('maps native generation failures to a network error', () async {
    llm.failure = PlatformException(
      code: 'generation_failed',
      message: 'runtime failed',
    );

    await expectLater(
      provider
          .explainMetrics(
            metrics: const {'symbol': 'SOLUSDT'},
            apiKey: '',
            languageCode: 'en',
            cancel: CancelSignal(),
          )
          .toList(),
      throwsA(
        isA<AiNetwork>().having(
          (error) => error.reason,
          'reason',
          contains('runtime failed'),
        ),
      ),
    );
  });
}

final class _FakeOnDeviceLlm implements OnDeviceLlmApi {
  String answer = 'Local answer';
  Object? failure;
  Completer<String>? pending;
  String? system;
  String? prompt;
  String? languageCode;
  int? maxOutputChars;
  bool cancelled = false;

  @override
  Future<OnDeviceAvailability> availability() async =>
      OnDeviceAvailability.available;

  @override
  Future<String> generate({
    required String system,
    required String prompt,
    required String languageCode,
    required int maxOutputChars,
  }) {
    this.system = system;
    this.prompt = prompt;
    this.languageCode = languageCode;
    this.maxOutputChars = maxOutputChars;
    if (failure case final error?) return Future<String>.error(error);
    return pending?.future ?? Future<String>.value(answer);
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    final generation = pending;
    if (generation != null && !generation.isCompleted) {
      generation.completeError(StateError('cancelled'));
    }
  }

  @override
  Future<String> runtimeName() async => 'fake';
}
