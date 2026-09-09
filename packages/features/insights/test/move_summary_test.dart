import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:domain/domain.dart';
import 'package:features_insights/features_insights.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';

/// Always answers with the given status and an error body; never streams.
final class _FailingTransport implements ClaudeTransport {
  _FailingTransport(this.status);

  final int status;
  int calls = 0;

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    calls++;
    return ClaudeResponse(
      status: status,
      body: Stream.value(utf8.encode('{"error":{"message":"nope"}}')),
    );
  }
}

/// Records the key it was handed; replays the bundled example otherwise.
final class _RecordingTransport implements ClaudeTransport {
  _RecordingTransport() : _inner = DemoClaudeTransport(delay: Duration.zero);

  final DemoClaudeTransport _inner;
  final keys = <String>[];

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) {
    keys.add(apiKey);
    return _inner.post(body, apiKey: apiKey, cancel: cancel);
  }
}

void main() {
  late FakeMarketDataSource source;
  late FakeSecretStore secrets;
  late FakeSettingsStore settings;
  late Instrument btc;
  final opened = <String>[];

  Widget app({
    ClaudeTransport? transport,
    bool aiEnabled = true,
    Locale locale = const Locale('en'),
  }) => testApp(
    locale: locale,
    overrides: [
      ...fakeOverrides(
        source: source,
        secrets: secrets,
        settings: settings,
        config: FakeInsightsConfigSource(
          InsightsConfig(
            insightsScreenJson: '{"schema":1,"children":[]}',
            aiInsightsEnabled: aiEnabled,
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
      body: MoveSummarySheet(
        instrument: btc,
        onOpenAiSettings: () => opened.add('settings'),
      ),
    ),
  );

  setUp(() {
    source = FakeMarketDataSource();
    secrets = FakeSecretStore();
    settings = FakeSettingsStore();
    btc = source.instrumentFor(defaultAssets.first, 'USDT');
    opened.clear();
  });

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('without a key it offers settings and the recorded example', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Add your Claude API key'), findsOneWidget);
    expect(find.byKey(const Key('ai_summary_text')), findsNothing);

    await tester.tap(find.byKey(const Key('ai_open_settings')));
    expect(opened, ['settings']);

    await tester.tap(find.byKey(const Key('ai_show_example')));
    await pumpUntil(tester, find.byKey(const Key('ai_structure')));

    expect(find.byKey(const Key('ai_demo_badge')), findsOneWidget);
    final text = tester
        .widget<SelectableText>(find.byKey(const Key('ai_summary_text')))
        .data!;
    expect(text, contains('BTC/USDT'));
    expect(find.byKey(const Key('ai_structure')), findsOneWidget);
    // The example is free: no cost line.
    expect(find.byKey(const Key('ai_cost')), findsNothing);
  });

  testWidgets('with a key but no consent it asks first, then runs', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-test';
    final transport = _RecordingTransport();
    await tester.pumpWidget(app(transport: transport));
    await tester.pump();
    await tester.pump();

    expect(find.text('Before the first summary'), findsOneWidget);
    expect(transport.keys, isEmpty);

    await tester.tap(find.byKey(const Key('ai_consent_agree')));
    await pumpUntil(tester, find.byKey(const Key('ai_summary_text')));

    expect(settings.values[SettingsKeys.aiConsent], 'true');
    expect(transport.keys, isNotEmpty);
    expect(transport.keys.toSet(), {'sk-ant-test'});
    expect(find.byKey(const Key('ai_demo_badge')), findsNothing);
  });

  testWidgets('with a key and consent it starts by itself', (tester) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    await tester.pumpWidget(app(transport: _RecordingTransport()));
    await pumpUntil(tester, find.byKey(const Key('ai_structure')));

    expect(find.byKey(const Key('ai_summary_text')), findsOneWidget);
    expect(find.textContaining('not financial advice'), findsOneWidget);
  });

  testWidgets('a refused key shows the "check the key" hint and retries', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-bad';
    settings.values[SettingsKeys.aiConsent] = 'true';
    final transport = _FailingTransport(401);
    await tester.pumpWidget(app(transport: transport));
    await pumpUntil(tester, find.byKey(const Key('ai_error')));

    expect(find.textContaining('API key was refused'), findsOneWidget);
    expect(transport.calls, 1);

    await tester.tap(find.byKey(const Key('ai_retry')));
    await pumpUntil(tester, find.byKey(const Key('ai_error')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(transport.calls, 2);
  });

  testWidgets('a rate limit is reported as "try again in a moment"', (
    tester,
  ) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    await tester.pumpWidget(app(transport: _FailingTransport(429)));
    await pumpUntil(tester, find.byKey(const Key('ai_error')));
    expect(find.textContaining('Too many requests'), findsOneWidget);
  });

  testWidgets('revoking consent mid-run stops the request', (tester) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    final gate = Completer<void>();
    await tester.pumpWidget(app(transport: _StallingTransport(gate)));
    await pumpUntil(tester, find.byKey(const Key('ai_stop')));
    expect(find.byKey(const Key('ai_stop')), findsOneWidget);

    await settings.delete(SettingsKeys.aiConsent);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Back to the consent gate, and the stream is no longer running.
    expect(find.byKey(const Key('ai_stop')), findsNothing);
    gate.complete();
    await tester.pump();
  });

  testWidgets('a second attempt keeps what the first one cost', (tester) async {
    secrets.values[SecretKeys.anthropicApiKey] = 'sk-ant-test';
    settings.values[SettingsKeys.aiConsent] = 'true';
    await tester.pumpWidget(app(transport: _BillingTransport()));
    await pumpUntil(tester, find.byKey(const Key('ai_cost')));
    final first = tester.widget<Text>(find.byKey(const Key('ai_cost'))).data!;

    await tester.tap(find.byKey(const Key('ai_retry')));
    String cost() =>
        tester.widget<Text>(find.byKey(const Key('ai_cost'))).data!;
    for (var i = 0; i < 60 && cost() == first; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final second = cost();
    expect(second, isNot(first), reason: 'the totals grew');
    expect(_tokensIn(second), _tokensIn(first) * 2);
  });

  testWidgets('the bundled example asset parses into a summary', (
    tester,
  ) async {
    final events =
        await MoveSummarySession(
              transport: DemoClaudeTransport(delay: Duration.zero),
              tools: _NoTools(),
              config: AiModelConfig.defaults,
              // A recorded example keeps the source it was recorded from.
              groundProvenance: false,
            )
            .run(
              instrument: btc,
              apiKey: 'demo',
              languageCode: 'ru',
              cancel: CancelSignal(),
            )
            .toList();

    expect(events.whereType<SummaryText>(), isNotEmpty);
    final structure = events.whereType<SummaryStructure>().single.structure;
    expect(structure.trend, Trend.up);
    expect(structure.dataSource, 'Binance');
    expect(structure.keyLevels, isNotEmpty);
  });

  testWidgets("a live summary shows the app's source, not the model's", (
    tester,
  ) async {
    final events =
        await MoveSummarySession(
              transport: DemoClaudeTransport(delay: Duration.zero),
              tools: _NoTools(),
              config: AiModelConfig.defaults,
            )
            .run(
              instrument: btc,
              apiKey: 'sk-test',
              languageCode: 'en',
              cancel: CancelSignal(),
            )
            .toList();

    // The asset says Binance; the tools say Demo, and the tools win.
    expect(
      events.whereType<SummaryStructure>().single.structure.dataSource,
      'Demo',
    );
  });
}

int _tokensIn(String costLine) =>
    int.parse(RegExp(r'(\d+) tokens').firstMatch(costLine)!.group(1)!);

/// Holds the first response open until the completer fires.
final class _StallingTransport implements ClaudeTransport {
  _StallingTransport(this.gate);

  final Completer<void> gate;

  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    final controller = StreamController<List<int>>();
    unawaited(gate.future.then((_) => unawaited(controller.close())));
    return ClaudeResponse(status: 200, body: controller.stream);
  }
}

/// Reports fixed token usage so the cost line is deterministic.
final class _BillingTransport implements ClaudeTransport {
  @override
  Future<ClaudeResponse> post(
    Map<String, Object?> body, {
    required String apiKey,
    required CancelSignal cancel,
  }) async {
    final structured = body.containsKey('output_config');
    final text = structured
        ? '{"trend":"up","volatility":"low","keyLevels":[],'
              '"dataSource":"Fake","dataAsOf":"2026-09-09T12:00:00Z"}'
        : 'Fixed prose.';
    String event(Map<String, Object?> e) =>
        'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n';
    final body_ = [
      {
        'type': 'message_start',
        'message': {
          'usage': {'input_tokens': 40, 'output_tokens': 0},
        },
      },
      {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'text', 'text': ''},
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': text},
      },
      {'type': 'content_block_stop', 'index': 0},
      {
        'type': 'message_delta',
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 10},
      },
      {'type': 'message_stop'},
    ].map(event).join();
    return ClaudeResponse(status: 200, body: Stream.value(utf8.encode(body_)));
  }
}

final class _NoTools implements MarketTools {
  @override
  List<Instrument> get instruments => const [];

  @override
  String get sourceName => 'Demo';

  @override
  Set<Interval> get intervals => const {};

  @override
  Future<List<Candle>> klines(
    Instrument instrument,
    Interval interval,
    int limit,
  ) async => const [];

  @override
  Future<OrderBookSnapshot?> orderBook(Instrument instrument) async => null;
}
