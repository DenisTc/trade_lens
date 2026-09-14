import 'dart:io';

import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

import '../support/fake_http_adapter.dart';

String _fixture(String name) =>
    File('test/fixtures/bybit/$name').readAsStringSync();

void main() {
  BybitMarketDataSource build(FakeHttpAdapter adapter) => BybitMarketDataSource(
    client: BybitRestClient(
      dio: createDio(baseUrl: BybitHosts.rest, adapter: adapter),
    ),
  );

  final btc = defaultAssets.first;
  final eth = defaultAssets[1];

  test('instruments are BASEQUOTE on the bybit source', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(500, '')),
    );

    expect(source.id, 'bybit');
    expect(source.instrumentFor(btc, 'USDT')?.symbol, 'BTCUSDT');
    expect(source.capabilities, Capabilities.full);
    expect(source.attribution, 'Data: Bybit');
  });

  test('klines come newest first on the wire and oldest first here', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('kline_60.json')),
    );
    final source = build(adapter);

    final result = await source.klines(
      source.instrumentFor(btc, 'USDT')!,
      Interval.h1,
      limit: 3,
    );

    final candles = result.valueOrNull!;
    expect(candles, hasLength(3));
    expect(candles.first.openTime.isBefore(candles.last.openTime), isTrue);
    final query = adapter.requests.single.uri.queryParameters;
    expect(query['category'], 'spot');
    expect(query['interval'], '60');
    expect(query['limit'], '3');
    expect(query.containsKey('end'), isFalse);
  });

  test('klines with `before` sets end one millisecond short', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('kline_60.json')),
    );
    final oldest = DateTime.utc(2026, 9, 11, 11);

    await build(adapter).klines(
      build(adapter).instrumentFor(btc, 'USDT')!,
      Interval.h1,
      before: oldest,
    );

    expect(
      adapter.requests.single.uri.queryParameters['end'],
      '${oldest.millisecondsSinceEpoch - 1}',
    );
  });

  test('quotes fetch the whole spot list once and keep the catalog', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('tickers.json')),
    );
    final source = build(adapter);

    final result = await source.quotes(source.instruments([btc, eth], 'USDT'));

    final quotes = result.valueOrNull!;
    expect(quotes.map((q) => q.instrument.symbol), ['BTCUSDT', 'ETHUSDT']);
    expect(quotes.first.change24hPct, isNotNull);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.queryParameters, {'category': 'spot'});
  });

  test('a non-zero retCode is an error, not an empty answer', () async {
    final source = build(
      FakeHttpAdapter(
        (_, _) => const FakeResponse(
          200,
          '{"retCode":10001,"retMsg":"params error","result":{}}',
        ),
      ),
    );

    final result = await source.klines(
      source.instrumentFor(btc, 'USDT')!,
      Interval.h1,
    );

    expect(result.errorOrNull, isA<Unavailable>());
    expect('${result.errorOrNull}', contains('10001'));
  });

  test('retCode 10006 is the rate limit', () async {
    final source = build(
      FakeHttpAdapter(
        (_, _) => const FakeResponse(
          200,
          '{"retCode":10006,"retMsg":"too many visits","result":{}}',
        ),
      ),
    );

    final result = await source.quotes(source.instruments([btc], 'USDT'));

    expect(result.errorOrNull, isA<RateLimited>());
  });

  test('451 is a region block, like everywhere else', () async {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(451, '{}')),
    );

    final result = await source.quotes(source.instruments([btc], 'USDT'));

    expect(
      result.errorOrNull,
      const MarketError.regionBlocked(sourceId: 'bybit'),
    );
  });
}
