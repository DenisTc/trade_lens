import 'dart:io';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

import '../support/fake_http_adapter.dart';

String _fixture(String name) =>
    File('test/fixtures/binance/$name').readAsStringSync();

void main() {
  BinanceMarketDataSource build(
    FakeHttpAdapter adapter, {
    BinanceHosts? hosts,
    Set<String>? listed,
  }) {
    final h = hosts ?? BinanceHosts.global;
    final dio = createDio(baseUrl: h.rest, adapter: adapter);
    return BinanceMarketDataSource(
      client: BinanceRestClient(dio: dio),
      hosts: h,
      listedSymbols: listed,
    );
  }

  final btc = defaultAssets.first;
  final eth = defaultAssets[1];

  test('instrumentFor builds BASEQUOTE symbols', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(500, '')),
    );
    expect(source.instrumentFor(btc, 'USDT')?.symbol, 'BTCUSDT');
    expect(source.instrumentFor(btc, 'USDT')?.sourceId, 'binance');
    expect(source.id, 'binance');
    expect(source.capabilities, Capabilities.full);
  });

  test('Binance.US returns null for unlisted pairs', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(500, '')),
      hosts: BinanceHosts.us,
      listed: {'BTCUSDT'},
    );
    expect(source.instrumentFor(btc, 'USDT'), isNotNull);
    expect(source.instrumentFor(eth, 'USDT'), isNull);
    expect(source.instruments([btc, eth], 'USDT'), hasLength(1));
    expect(source.id, 'binance_us');
  });

  test('quotes hits ticker/24hr with a JSON symbols array', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('ticker_24hr.json')),
    );
    final source = build(adapter);
    final instruments = source.instruments([btc, eth], 'USDT');

    final result = await source.quotes(instruments);

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v3/ticker/24hr');
    expect(request.uri.queryParameters['symbols'], '["BTCUSDT","ETHUSDT"]');
    final quotes = result.valueOrNull!;
    expect(quotes.map((q) => q.instrument.symbol), ['BTCUSDT', 'ETHUSDT']);
    expect(quotes.first.price, isA<Decimal>());
  });

  test('klines passes interval code and limit', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('klines_1m.json')),
    );
    final source = build(adapter);

    final result = await source.klines(
      source.instrumentFor(btc, 'USDT')!,
      Interval.m15,
      limit: 3,
    );

    final query = adapter.requests.single.uri.queryParameters;
    expect(query, {'symbol': 'BTCUSDT', 'interval': '15m', 'limit': '3'});
    expect(result.valueOrNull, hasLength(3));
  });

  test('klines refuses Interval.auto', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(200, '[]')),
    );
    expect(
      () => source.klines(source.instrumentFor(btc, 'USDT')!, Interval.auto),
      throwsArgumentError,
    );
  });

  test('451 becomes RegionBlocked', () async {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(451, '{}')),
    );
    final result = await source.quotes(source.instruments([btc], 'USDT'));
    expect(
      result.errorOrNull,
      const MarketError.regionBlocked(sourceId: 'binance'),
    );
  });

  test('timeout becomes Unavailable, not RegionBlocked', () async {
    final source = build(
      FakeHttpAdapter(
        (options, _) =>
            throw fakeDioError(options, DioExceptionType.receiveTimeout),
      ),
    );
    final result = await source.quotes(source.instruments([btc], 'USDT'));
    expect(
      result.errorOrNull,
      isA<Unavailable>().having((e) => e.reason, 'reason', 'timeout'),
    );
  });

  test('418 becomes RateLimited with the ban duration', () async {
    final source = build(
      FakeHttpAdapter(
        (_, _) => const FakeResponse(418, '{}', headers: {'Retry-After': '90'}),
      ),
    );
    final result = await source.quotes(source.instruments([btc], 'USDT'));
    expect(
      result.errorOrNull,
      isA<RateLimited>().having(
        (e) => e.retryAfter,
        'retryAfter',
        const Duration(seconds: 90),
      ),
    );
  });

  test('malformed payload becomes ParseFailure', () async {
    final source = build(
      FakeHttpAdapter(
        (_, _) =>
            const FakeResponse(200, '[{"symbol":"BTCUSDT","lastPrice":1}]'),
      ),
    );
    final result = await source.quotes(source.instruments([btc], 'USDT'));
    expect(result.errorOrNull, isA<ParseFailure>());
  });

  test('[null] payload is a ParseFailure, not a TypeError', () async {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(200, '[null]')),
    );
    final quotes = await source.quotes(source.instruments([btc], 'USDT'));
    expect(quotes.errorOrNull, isA<ParseFailure>());
    final klines = await source.klines(
      source.instrumentFor(btc, 'USDT')!,
      Interval.m1,
    );
    expect(klines.errorOrNull, isA<ParseFailure>());
  });

  test('streams are not wired before ws_client lands', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(200, '[]')),
    );
    expect(
      () => source.tradeStream(source.instrumentFor(btc, 'USDT')!),
      throwsUnimplementedError,
    );
  });
}
