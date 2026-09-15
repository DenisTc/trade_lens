import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BacktestMetrics _metrics() => BacktestMetrics.fromResult(
  BacktestResult(
    capital: Decimal.fromInt(1000),
    trades: const [],
    equity: const [],
    finalEquity: Decimal.fromInt(1050),
    fees: Decimal.fromInt(5),
    maxDrawdown: Decimal.fromInt(20),
    baseHeld: Decimal.one,
    quoteHeld: Decimal.fromInt(950),
  ),
  kind: 'grid',
  params: const {'lower': '90', 'upper': '110', 'levels': '5'},
  symbol: 'BTCUSDT',
  intervalCode: '1h',
  candleCount: 60,
  from: DateTime.utc(2026, 9, 9),
  to: DateTime.utc(2026, 9, 12),
);

final class _StallingTransport implements ClaudeTransport {
  CancelSignal? signal;
  final stream = StreamController<List<int>>();

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    signal = cancel;
    return ClaudeResponse(status: 200, body: stream.stream);
  }
}

final class _FakeSummaryProvider implements SummaryProvider {
  @override
  Usage get usage => const Usage(inputTokens: 12, outputTokens: 3);

  @override
  double get costUsd => 0.002;

  @override
  Stream<SummaryEvent> explainMetrics({
    required Map<String, Object?> metrics,
    required String apiKey,
    required String languageCode,
    required CancelSignal cancel,
  }) async* {
    yield const SummaryText('Injected ');
    yield SummaryText('${metrics['symbol']} summary in $languageCode.');
    yield SummaryUsage(usage: usage, costUsd: costUsd);
    yield const SummaryDone();
  }
}

void main() {
  late FakeSecretStore secrets;
  late FakeSettingsStore settings;
  var opened = false;

  Widget app({
    ClaudeTransport? transport,
    bool enabled = true,
    Locale locale = const Locale('en'),
  }) => testApp(
    locale: locale,
    overrides: [
      ...fakeOverrides(
        source: FakeMarketDataSource(),
        secrets: secrets,
        settings: settings,
        config: FakeInsightsConfigSource(
          InsightsConfig(
            insightsScreenJson: '{"schema":1,"children":[]}',
            aiInsightsEnabled: enabled,
            source: InsightsConfigOrigin.remote,
          ),
        ),
      ),
      demoClaudeTransportProvider.overrideWithValue(
        DemoClaudeTransport(delay: Duration.zero),
      ),
      if (transport != null)
        claudeTransportProvider.overrideWithValue(transport),
    ],
    home: Scaffold(
      body: BacktestExplanationSheet(
        metrics: _metrics(),
        onOpenAiSettings: () => opened = true,
      ),
    ),
  );

  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsOneWidget);
  }

  setUp(() {
    secrets = FakeSecretStore();
    settings = FakeSettingsStore();
    opened = false;
  });

  test('overridden summary factory streams into controller state', () async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-test';
    final transport = _StallingTransport();
    final container = ProviderContainer(
      overrides: [
        secretStoreProvider.overrideWithValue(secrets),
        aiReadinessProvider.overrideWithValue(AiReadiness.ready),
        claudeTransportProvider.overrideWithValue(transport),
        aiModelConfigProvider.overrideWithValue(AiModelConfig.defaults),
        summaryProviderFactoryProvider.overrideWithValue((actual, config) {
          expect(actual, same(transport));
          expect(config, AiModelConfig.defaults);
          return _FakeSummaryProvider();
        }),
      ],
    );
    addTearDown(container.dispose);
    final provider = backtestExplanationControllerProvider(UniqueKey());
    final states = <BacktestExplanationState>[];
    final subscription = container.listen(
      provider,
      (_, next) => states.add(next),
    );
    addTearDown(subscription.close);

    await container
        .read(provider.notifier)
        .start(metrics: _metrics(), languageCode: 'vi');

    expect(states.map((state) => state.text), contains('Injected '));
    final state = container.read(provider);
    expect(state.text, 'Injected BTCUSDT summary in vi.');
    expect(state.usage, const Usage(inputTokens: 12, outputTokens: 3));
    expect(state.costUsd, 0.002);
    expect(state.running, isFalse);
    expect(state.error, isNull);
    expect(state.demo, isFalse);
  });

  testWidgets('no key offers settings', (tester) async {
    await tester.pumpWidget(app());
    await until(tester, find.byKey(const Key('ai_open_settings')));
    await tester.tap(find.byKey(const Key('ai_open_settings')));
    expect(opened, isTrue);
  });

  for (final (language, word) in [
    ('en', 'grid'),
    ('ru', 'сетка'),
    ('vi', 'lưới'),
  ]) {
    testWidgets('example replays backtest prose in $language', (tester) async {
      await tester.pumpWidget(app(locale: Locale(language)));
      await until(tester, find.byKey(const Key('ai_show_example')));
      await tester.tap(find.byKey(const Key('ai_show_example')));
      await until(tester, find.byKey(const Key('ai_retry')));
      final prose = tester
          .widget<SelectableText>(find.byKey(const Key('ai_summary_text')))
          .data!;
      expect(prose, contains(word));
      expect(find.byKey(const Key('ai_demo_badge')), findsOneWidget);
      expect(find.byKey(const Key('ai_structure')), findsNothing);
      expect(find.byKey(const Key('ai_error')), findsNothing);
      expect(find.byKey(const Key('ai_cost')), findsNothing);
    });
  }

  testWidgets('a running explanation can be stopped before any text', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    final transport = _StallingTransport();
    await tester.pumpWidget(app(transport: transport));
    await until(tester, find.byKey(const Key('ai_stop')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai_stop')));
    await until(tester, find.byKey(const Key('ai_retry')));
    expect(transport.signal!.isCancelled, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('ai_stop')), findsNothing);
    unawaited(transport.stream.close());
  });

  testWidgets('live provider demo override replays the backtest asset', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    await tester.pumpWidget(
      app(transport: DemoClaudeTransport(delay: Duration.zero)),
    );
    await until(tester, find.byKey(const Key('ai_retry')));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('ai_summary_text')))
          .data,
      contains('grid run'),
    );
    expect(find.byKey(const Key('ai_demo_badge')), findsOneWidget);
    expect(find.byKey(const Key('ai_structure')), findsNothing);
    expect(find.byKey(const Key('ai_error')), findsNothing);
  });

  testWidgets('revoking consent cancels a live explanation', (tester) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    final transport = _StallingTransport();
    await tester.pumpWidget(app(transport: transport));
    await until(tester, find.byKey(const Key('ai_stop')));
    await tester.pump();
    await settings.delete(SettingsKeys.aiConsent);
    await until(tester, find.byKey(const Key('ai_retry')));
    expect(transport.signal!.isCancelled, isTrue);
    unawaited(transport.stream.close());
  });

  testWidgets('chosen backtest asset emits only prose SSE events', (
    tester,
  ) async {
    final response = await DemoClaudeTransport(
      asset: demoBacktestAsset,
      delay: Duration.zero,
    ).post(const {}, apiKey: 'demo', cancel: CancelSignal());
    final events = await response.body.transform(const SseDecoder()).toList();
    expect(events.map((event) => event.event).toSet(), {
      'message_start',
      'content_block_start',
      'content_block_delta',
      'content_block_stop',
      'message_delta',
      'message_stop',
    });
    expect(events.first.event, 'message_start');
    expect(events.last.event, 'message_stop');
    final parsed = events.map(ClaudeStreamEvent.parse).toList();
    expect(
      parsed.whereType<TextDelta>().map((e) => e.text).join(),
      contains('grid run'),
    );
    expect(parsed.whereType<MessageDelta>().single.usage, const Usage());
    expect(parsed.whereType<BlockStart>().single.kind, BlockKind.text);
  });

  testWidgets('no consent waits and disabled still offers an example', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-test';
    await tester.pumpWidget(app());
    await until(tester, find.byKey(const Key('ai_consent_agree')));
    await tester.pumpWidget(app(enabled: false));
    await until(tester, find.text('The summary is off'));
    expect(find.byKey(const Key('ai_consent_agree')), findsNothing);
    expect(find.byKey(const Key('ai_show_example')), findsOneWidget);
  });
}
