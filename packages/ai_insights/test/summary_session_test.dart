import 'dart:async';

import 'package:ai_insights/ai_insights.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const config = AiModelConfig(
    model: 'claude-test',
    inputUsdPerMTok: 1,
    outputUsdPerMTok: 5,
  );
  const structure =
      '{"trend":"up","volatility":"medium","keyLevels":["100","101"],'
      '"dataSource":"fake","dataAsOf":"2026-09-09T12:00:00Z"}';

  Future<List<SummaryEvent>> run(
    FakeTransport transport, {
    FakeTools? tools,
    AiModelConfig cfg = config,
    CancelSignal? cancel,
  }) =>
      MoveSummarySession(
            transport: transport,
            tools: tools ?? FakeTools(),
            config: cfg,
          )
          .run(
            instrument: btc,
            apiKey: 'sk-test',
            languageCode: 'ru',
            cancel: cancel ?? CancelSignal(),
          )
          .toList();

  test('two tool iterations, streamed prose, structured block, cost', () async {
    final tools = FakeTools();
    final transport = FakeTransport([
      (_) => ok(
        sse(
          toolTurn(ToolSchemas.getKlines, {
            'instrument': 'BTCUSDT',
            'interval': '1h',
            'limit': 60,
          }, preface: 'Смотрю свечи. '),
        ),
      ),
      (_) => ok(
        sse(
          toolTurn(ToolSchemas.getOrderBook, {
            'instrument': 'btcusdt',
          }, id: 'toolu_2'),
        ),
      ),
      (_) => ok(sse(textTurn('Цена выросла на два процента за сутки.'))),
      (_) => ok(sse(textTurn(structure))),
    ]);

    final events = await run(transport, tools: tools);

    final text = events.whereType<SummaryText>().map((e) => e.delta).join();
    expect(text, startsWith('Смотрю свечи. '));
    expect(text, contains('Цена выросла'));
    expect(events.whereType<SummaryToolCall>().map((e) => e.call.name), [
      ToolSchemas.getKlines,
      ToolSchemas.getOrderBook,
    ]);
    expect(tools.calls, ['klines BTCUSDT 1h 60', 'book BTCUSDT']);
    expect(
      events.whereType<SummaryStructure>().single.structure.trend,
      Trend.up,
    );
    final usage = events.whereType<SummaryUsage>().single;
    expect(usage.usage, const Usage(inputTokens: 600, outputTokens: 100));
    expect(usage.costUsd, closeTo(600 / 1e6 * 1 + 100 / 1e6 * 5, 1e-12));
    expect(events.last, isA<SummaryDone>());

    // Requests: the loop echoes tool_use and tool_result, the structured
    // call carries the schema and no tools, the key goes in each call.
    expect(transport.requests, hasLength(4));
    final second = transport.requests[1]['messages']! as List<Object?>;
    expect(second, hasLength(3));
    final assistant = second[1]! as Map<String, Object?>;
    final content = assistant['content']! as List<Object?>;
    expect((content.last! as Map)['type'], 'tool_use');
    final result = (second[2]! as Map)['content']! as List<Object?>;
    expect((result.single! as Map)['tool_use_id'], 'toolu_1');
    expect(
      (result.single! as Map)['content']! as String,
      contains('interval=1h'),
    );
    expect(transport.requests[3].containsKey('tools'), isFalse);
    expect(
      ((transport.requests[3]['output_config']! as Map)['format']!
          as Map)['type'],
      'json_schema',
    );
    expect(transport.requests[0]['system'], contains('"ru"'));
    expect(transport.keys.toSet(), {'sk-test'});
  });

  test('stops at the iteration limit', () async {
    ClaudeResponse loop(Map<String, Object?> _) => ok(
      sse(
        toolTurn(ToolSchemas.getKlines, {
          'instrument': 'BTCUSDT',
          'interval': '1h',
          'limit': 10,
        }),
      ),
    );
    final transport = FakeTransport([loop, loop, loop, loop, loop]);
    expect(
      () => run(transport),
      throwsA(
        isA<AiBudgetExceeded>().having(
          (e) => e.what,
          'what',
          contains('iterations'),
        ),
      ),
    );
  });

  test(
    'invalid structured JSON keeps the prose and reports the failure',
    () async {
      final transport = FakeTransport([
        (_) => ok(sse(textTurn('Ровный день.'))),
        (_) => ok(sse(textTurn('{"trend":"sideways","volatility":"low"'))),
      ]);
      final events = await run(transport);
      expect(events.whereType<SummaryText>(), isNotEmpty);
      expect(events.whereType<SummaryStructure>(), isEmpty);
      expect(
        events.whereType<SummaryStructureFailed>().single.reason,
        contains('invalid JSON'),
      );
      expect(events.last, isA<SummaryDone>());
    },
  );

  test('a wrong enum in the structured block is rejected', () {
    expect(
      MoveStructure.parse(
        '{"trend":"moon","volatility":"low","keyLevels":[],"dataSource":"x","dataAsOf":"2026-09-09T00:00:00Z"}',
      ),
      const Err<MoveStructure, String>('trend'),
    );
  });

  test('HTTP errors map to the spec hints', () async {
    for (final (status, matcher) in [
      (401, isA<AiUnauthorized>()),
      (403, isA<AiUnauthorized>()),
      (
        429,
        isA<AiRateLimited>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 7),
        ),
      ),
      (500, isA<AiNetwork>()),
      (
        400,
        isA<AiBadRequest>().having((e) => e.message, 'message', 'bad model'),
      ),
    ]) {
      final transport = FakeTransport([
        (_) => http(
          status,
          '{"type":"error","error":{"type":"x","message":"bad model"}}',
          headers: {'retry-after': '7'},
        ),
      ]);
      await expectLater(run(transport), throwsA(matcher), reason: '$status');
    }
  });

  test('a transport exception is a network error', () {
    final transport = FakeTransport([(_) => throw StateError('offline')]);
    expect(() => run(transport), throwsA(isA<AiNetwork>()));
  });

  test('a refusal stop reason is surfaced', () {
    final transport = FakeTransport([
      (_) => ok(sse(textTurn('нет', stopReason: 'refusal'))),
    ]);
    expect(() => run(transport), throwsA(isA<AiRefused>()));
  });

  test('a truncated stream is an invalid response', () {
    final transport = FakeTransport([
      (_) => ok(sse(textTurn('x').sublist(0, 3))),
    ]);
    expect(() => run(transport), throwsA(isA<AiInvalidResponse>()));
  });

  test('the token budget stops the session', () {
    final transport = FakeTransport([
      (_) => ok(sse(textTurn('x', inputTokens: 50000))),
    ]);
    expect(() => run(transport), throwsA(isA<AiBudgetExceeded>()));
  });

  test('cancel ends the stream with AiCancelled', () async {
    final cancel = CancelSignal();
    final transport = FakeTransport([
      (_) {
        cancel.cancel();
        return ok(sse(textTurn('never shown')));
      },
    ]);
    expect(() => run(transport, cancel: cancel), throwsA(isA<AiCancelled>()));
  });

  test('a structured-call failure does not lose the prose', () async {
    final transport = FakeTransport([
      (_) => ok(sse(textTurn('Прозa есть.'))),
      (_) => http(429, '{}'),
    ]);
    final events = await run(transport);
    expect(events.whereType<SummaryStructureFailed>(), hasLength(1));
    expect(events.last, isA<SummaryDone>());
  });

  test('tool runner validates arguments and renders compact text', () async {
    final tools = FakeTools(book: false);
    final runner = ToolRunner(tools);
    expect(
      await runner.run(
        const ToolCall(
          id: '1',
          name: ToolSchemas.getKlines,
          input: {'instrument': 'DOGEUSDT', 'interval': '1h', 'limit': 10},
        ),
      ),
      'error: unknown instrument',
    );
    expect(
      await runner.run(
        const ToolCall(
          id: '1',
          name: ToolSchemas.getKlines,
          input: {'instrument': 'BTCUSDT', 'interval': '1w', 'limit': 10},
        ),
      ),
      'error: unknown interval',
    );
    expect(
      await runner.run(
        const ToolCall(
          id: '1',
          name: ToolSchemas.getOrderBook,
          input: {'instrument': 'BTCUSDT'},
        ),
      ),
      'unavailable',
    );
    expect(
      await runner.run(
        const ToolCall(
          id: '1',
          name: 'rm_rf',
          input: {'instrument': 'BTCUSDT'},
        ),
      ),
      'error: unknown tool',
    );
    // limit is clamped up to the schema minimum of 5; the fake holds 3.
    final klines = await runner.run(
      const ToolCall(
        id: '1',
        name: ToolSchemas.getKlines,
        input: {'instrument': 'BTCUSDT', 'interval': '15m', 'limit': 2},
      ),
    );
    // A source= line, the header and the three candles the fake holds.
    expect(klines.split('\n').where((l) => l.isNotEmpty), hasLength(5));
    expect(klines, startsWith('source=Fake Exchange'));
    expect(klines, contains('2026-09-09T00:00,100,101,99,100.5,12.5'));
  });

  test('model config parses partially and falls back on junk', () {
    expect(AiModelConfig.parse(null), AiModelConfig.defaults);
    expect(AiModelConfig.parse('{'), AiModelConfig.defaults);
    final parsed = AiModelConfig.parse(
      '{"model":"claude-sonnet-5","inputUsdPerMTok":3,"maxToolIterations":2,"junk":1}',
    );
    expect(parsed.model, 'claude-sonnet-5');
    expect(parsed.inputUsdPerMTok, 3);
    expect(parsed.outputUsdPerMTok, AiModelConfig.defaults.outputUsdPerMTok);
    expect(parsed.maxToolIterations, 2);
  });

  test('cumulative output usage is billed once', () async {
    // The API reports a running total per message; two deltas of 10 then
    // 25 mean 25 output tokens, not 35.
    final transport = FakeTransport([
      (_) => ok(
        sse([
          {
            'type': 'message_start',
            'message': {
              'usage': {'input_tokens': 100, 'output_tokens': 0},
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
            'delta': {'type': 'text_delta', 'text': 'ok'},
          },
          {'type': 'content_block_stop', 'index': 0},
          {
            'type': 'message_delta',
            'delta': <String, Object?>{},
            'usage': {'output_tokens': 10},
          },
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 25},
          },
          {'type': 'message_stop'},
        ]),
      ),
      (_) => ok(sse(textTurn(structure, inputTokens: 0, outputTokens: 0))),
    ]);
    final events = await run(transport);
    expect(
      events.whereType<SummaryUsage>().single.usage,
      const Usage(inputTokens: 100, outputTokens: 25),
    );
  });

  test('exactly maxToolIterations tool rounds are executed', () async {
    final tools = FakeTools();
    ClaudeResponse toolCall(Map<String, Object?> _) => ok(
      sse(
        toolTurn(ToolSchemas.getKlines, {
          'instrument': 'BTCUSDT',
          'interval': '1h',
          'limit': 10,
        }),
      ),
    );
    // Two tool rounds, then prose, then the structured call: within a
    // limit of two, nothing is thrown.
    final within = FakeTransport([
      toolCall,
      toolCall,
      (_) => ok(sse(textTurn('Готово.'))),
      (_) => ok(sse(textTurn(structure))),
    ]);
    await run(
      within,
      tools: tools,
      cfg: const AiModelConfig(
        model: 'claude-test',
        inputUsdPerMTok: 1,
        outputUsdPerMTok: 5,
        maxToolIterations: 2,
      ),
    );
    expect(tools.calls, hasLength(2));

    // A third request that asks for tools again is refused.
    final over = FakeTransport([toolCall, toolCall, toolCall]);
    await expectLater(
      run(
        over,
        cfg: const AiModelConfig(
          model: 'claude-test',
          inputUsdPerMTok: 1,
          outputUsdPerMTok: 5,
          maxToolIterations: 2,
        ),
      ),
      throwsA(isA<AiBudgetExceeded>()),
    );
    expect(over.requests, hasLength(3));
  });

  test('usage stays readable after a failure, for the cost line', () async {
    final transport = FakeTransport([
      (_) => ok(sse(textTurn('x', inputTokens: 120, outputTokens: 8))),
      (_) => http(500, '{}'),
      (_) => http(500, '{}'),
    ]);
    final session = MoveSummarySession(
      transport: transport,
      tools: FakeTools(),
      config: config,
    );
    // The structured call fails, which is tolerated; the prose call was
    // still billed.
    await session
        .run(
          instrument: btc,
          apiKey: 'sk-test',
          languageCode: 'en',
          cancel: CancelSignal(),
        )
        .toList();
    expect(session.usage, const Usage(inputTokens: 120, outputTokens: 8));
    expect(session.costUsd, greaterThan(0));
  });

  test('cancelling a stalled stream ends the run', () async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    final cancel = CancelSignal();
    final transport = FakeTransport([
      (_) => ClaudeResponse(status: 200, body: controller.stream),
    ]);
    final events =
        MoveSummarySession(
          transport: transport,
          tools: FakeTools(),
          config: config,
        ).run(
          instrument: btc,
          apiKey: 'sk-test',
          languageCode: 'en',
          cancel: cancel,
        );
    final done = expectLater(events.toList(), throwsA(isA<AiCancelled>()));
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    await done;
  });
}
