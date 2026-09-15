import 'dart:async';
import 'dart:convert';

import 'package:ai_insights/ai_insights.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const config = AiModelConfig(
    model: 'claude-test',
    inputUsdPerMTok: 1,
    outputUsdPerMTok: 5,
  );
  const metrics = <String, Object?>{'kind': 'grid', 'netProfit': '50'};
  MetricsSummarySession session(FakeTransport transport) =>
      MetricsSummarySession(transport: transport, config: config);
  Future<List<SummaryEvent>> run(
    SummaryProvider provider, {
    CancelSignal? cancel,
  }) => provider
      .explainMetrics(
        metrics: metrics,
        apiKey: 'sk-test',
        languageCode: 'ru',
        cancel: cancel ?? CancelSignal(),
      )
      .toList();

  test(
    'one Messages call carries only fenced metrics and streams prose with cost',
    () async {
      final transport = FakeTransport([
        (_) => ok(sse(textTurn('Результат сетки.'))),
      ]);
      final provider = session(transport);
      final events = await run(provider);
      expect(
        events.whereType<SummaryText>().map((e) => e.delta).join(),
        'Результат сетки. ',
      );
      expect(
        events.whereType<SummaryUsage>().single.usage,
        const Usage(inputTokens: 100, outputTokens: 20),
      );
      expect(provider.costUsd, closeTo(0.0002, 1e-12));
      expect(events.last, isA<SummaryDone>());
      expect(transport.requests, hasLength(1));
      final request = transport.requests.single;
      expect(request['stream'], true);
      expect(request.containsKey('tools'), false);
      expect(request.containsKey('output_config'), false);
      expect(request['system'], contains('code "ru"'));
      expect(request['system'], contains('ADR-0005'));
      final message = (request['messages']! as List).single as Map;
      expect(
        message['content'],
        contains('```json\n${jsonEncode(metrics)}\n```'),
      );
      expect(transport.keys, ['sk-test']);
    },
  );

  for (final (status, matcher) in [
    (401, isA<AiUnauthorized>()),
    (429, isA<AiRateLimited>()),
    (400, isA<AiBadRequest>()),
    (500, isA<AiNetwork>()),
  ]) {
    test(
      'maps HTTP $status',
      () => expectLater(
        run(
          session(
            FakeTransport([
              (_) => http(status, '{"error":{"message":"failure"}}'),
            ]),
          ),
        ),
        throwsA(matcher),
      ),
    );
  }
  for (final (reason, matcher) in [
    ('refusal', isA<AiRefused>()),
    ('max_tokens', isA<AiBudgetExceeded>()),
  ]) {
    test('reports $reason and retains billed usage', () async {
      final provider = session(
        FakeTransport([
          (_) => ok(sse(textTurn('partial', stopReason: reason))),
        ]),
      );
      await expectLater(run(provider), throwsA(matcher));
      expect(provider.usage.total, 120);
    });
  }
  test('rejects a truncated stream', () async {
    final provider = session(
      FakeTransport([(_) => ok(sse(textTurn('partial')..removeLast()))]),
    );
    await expectLater(run(provider), throwsA(isA<AiInvalidResponse>()));
    expect(provider.usage.total, 120);
  });
  test('cumulative output tokens are counted once', () async {
    final turn = textTurn('Result', outputTokens: 25);
    turn.insert(turn.length - 2, {
      'type': 'message_delta',
      'usage': {'output_tokens': 10},
    });
    final provider = session(FakeTransport([(_) => ok(sse(turn))]));
    await run(provider);
    expect(provider.usage, const Usage(inputTokens: 100, outputTokens: 25));
  });
  test('cancellation interrupts a silent stream', () async {
    final stream = StreamController<List<int>>();
    addTearDown(stream.close);
    final provider = session(
      FakeTransport([(_) => ClaudeResponse(status: 200, body: stream.stream)]),
    );
    final cancel = CancelSignal();
    final done = expectLater(
      run(provider, cancel: cancel),
      throwsA(isA<AiCancelled>()),
    );
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await done;
  });
}
