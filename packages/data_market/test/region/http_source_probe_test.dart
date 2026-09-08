import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../support/fake_http_adapter.dart';

void main() {
  final candidate = SourceCandidate(
    id: 'binance_global',
    sourceId: 'binance',
    restPing: Uri.parse('https://api.binance.com/api/v3/ping'),
    wsProbe: Uri.parse(
      'wss://stream.binance.com:9443/stream?streams=btcusdt@miniTicker',
    ),
  );

  HttpSourceProbe build(FakeHttpAdapter adapter, {bool wsAlive = true}) =>
      HttpSourceProbe(
        adapter: adapter,
        wsHandshake: (url, timeout) async {
          expect(url, candidate.wsProbe);
          expect(timeout, const Duration(seconds: 3));
          return wsAlive;
        },
      );

  test('200 + live WebSocket → ok', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(200, '{}'));
    expect(await build(adapter).probe(candidate), ProbeOutcome.ok);
    expect(
      adapter.requests.single.uri.toString(),
      candidate.restPing.toString(),
    );
  });

  test('200 + silent WebSocket → unavailable, not ok', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(200, '{}'));
    expect(
      await build(adapter, wsAlive: false).probe(candidate),
      ProbeOutcome.unavailable,
    );
  });

  test('451 → regionBlocked and the WebSocket is not tried', () async {
    var wsCalled = false;
    final probe = HttpSourceProbe(
      adapter: FakeHttpAdapter((_, _) => const FakeResponse(451, '{}')),
      wsHandshake: (_, _) async => wsCalled = true,
    );
    expect(await probe.probe(candidate), ProbeOutcome.regionBlocked);
    expect(wsCalled, isFalse);
  });

  test('timeout → unavailable without retries', () async {
    final adapter = FakeHttpAdapter(
      (options, _) =>
          throw fakeDioError(options, DioExceptionType.connectionTimeout),
    );
    expect(await build(adapter).probe(candidate), ProbeOutcome.unavailable);
    expect(adapter.requests, hasLength(1), reason: 'the resolver owns retries');
  });

  test('5xx → unavailable', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(503, '{}'));
    expect(await build(adapter).probe(candidate), ProbeOutcome.unavailable);
  });

  test('REST-only candidate is ok on 200 alone', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(200, '{}'));
    expect(await build(adapter).probe(coinGeckoFallback), ProbeOutcome.ok);
  });
}
