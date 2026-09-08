// Tests drive futures with fakeAsync and pump them by hand.
// ignore_for_file: discarded_futures

import 'dart:io';

import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../support/fake_http_adapter.dart';

String _fixture(String name) =>
    File('test/fixtures/coingecko/$name').readAsStringSync();

void main() {
  CoinGeckoMarketDataSource build(FakeHttpAdapter adapter, {String key = ''}) {
    final dio = createDio(
      baseUrl: CoinGeckoRestClient.baseUrl,
      adapter: adapter,
    );
    return CoinGeckoMarketDataSource(
      client: CoinGeckoRestClient(dio: dio, demoKey: key),
    );
  }

  final btc = defaultAssets.first;

  test('maps the whole default catalog to CoinGecko ids', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(500, '')),
    );
    final instruments = source.instruments(defaultAssets, 'USD');
    expect(instruments, hasLength(defaultAssets.length));
    expect(instruments.first.symbol, 'bitcoin');
    expect(instruments.first.quote, 'USD');
    expect(source.instrumentFor(btc, 'USDT'), isNull, reason: 'only usd');
    expect(source.capabilities, Capabilities.pricesOnly);
    expect(source.attribution, 'Powered by CoinGecko');
  });

  test(
    'quotes batches ids in one simple/price call with the demo key',
    () async {
      final adapter = FakeHttpAdapter(
        (_, _) => FakeResponse(200, _fixture('simple_price.json')),
      );
      final source = build(adapter, key: 'demo-123');

      final result = await source.quotes(
        source.instruments(defaultAssets.take(2).toList(), 'USD'),
      );

      final request = adapter.requests.single;
      expect(request.uri.path, '/api/v3/simple/price');
      expect(request.uri.queryParameters['ids'], 'bitcoin,ethereum');
      expect(request.uri.queryParameters['include_24hr_change'], 'true');
      expect(request.headers['x-cg-demo-api-key'], 'demo-123');
      expect(result.valueOrNull, hasLength(2));
    },
  );

  test('omits the key header when empty', () async {
    final adapter = FakeHttpAdapter((_, _) => const FakeResponse(200, '{}'));
    await build(adapter).quotes(build(adapter).instruments([btc], 'USD'));
    expect(
      adapter.requests.single.headers.containsKey('x-cg-demo-api-key'),
      isFalse,
    );
  });

  test('klines asks for days per interval and shifts to openTime', () async {
    final adapter = FakeHttpAdapter(
      (_, _) => FakeResponse(200, _fixture('ohlc_1d.json')),
    );
    final source = build(adapter);

    final result = await source.klines(
      source.instrumentFor(btc, 'USD')!,
      Interval.auto,
    );

    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v3/coins/bitcoin/ohlc');
    expect(request.uri.queryParameters, {'vs_currency': 'usd', 'days': '1'});
    expect(result.valueOrNull!.first.volume, isNull);
    expect(CoinGeckoMarketDataSource.daysFor(Interval.h1), 7);
    expect(CoinGeckoMarketDataSource.daysFor(Interval.d1), 90);
  });

  test('429 is QuotaExhausted, never a silent spinner', () async {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(429, '{}')),
    );
    final result = await source.quotes(source.instruments([btc], 'USD'));
    expect(
      result.errorOrNull,
      const MarketError.quotaExhausted(sourceId: 'coingecko'),
    );
  });

  test('451 is still RegionBlocked', () async {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(451, '{}')),
    );
    final result = await source.quotes(source.instruments([btc], 'USD'));
    expect(
      result.errorOrNull,
      const MarketError.regionBlocked(sourceId: 'coingecko'),
    );
  });

  test('quoteStream polls immediately and every 60 s, stops on cancel', () {
    fakeAsync((async) {
      final adapter = FakeHttpAdapter(
        (_, _) => FakeResponse(200, _fixture('simple_price.json')),
      );
      final source = build(adapter);
      final received = <Quote>[];
      final sub = source
          .quoteStream(source.instruments([btc], 'USD'))
          .listen(received.add);

      // Dio schedules its timeouts on the fake clock: advance a tick.
      async.elapse(const Duration(milliseconds: 1));
      expect(adapter.requests, hasLength(1));
      expect(received, hasLength(1));

      async.elapse(const Duration(seconds: 60));
      expect(adapter.requests, hasLength(2));
      expect(received, hasLength(2));

      sub.cancel();
      async.elapse(const Duration(minutes: 5));
      expect(adapter.requests, hasLength(2), reason: 'no polling after cancel');
    });
  });

  test(
    'cancelling the quote stream completes (no close/onCancel loop)',
    () async {
      // Real time on purpose: cancel() returns a root-zone future that a fake
      // clock never drives, and the bug this guards against is a real hang.
      final adapter = FakeHttpAdapter(
        (_, _) => FakeResponse(200, _fixture('simple_price.json')),
      );
      final source = build(adapter);
      final sub = source
          .quoteStream(source.instruments([btc], 'USD'))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await sub.cancel().timeout(const Duration(seconds: 2));
    },
  );

  test('several quote streams share one batched request per cycle', () {
    fakeAsync((async) {
      final adapter = FakeHttpAdapter(
        (_, _) => FakeResponse(200, _fixture('simple_price.json')),
      );
      final source = build(adapter);
      final instruments = source.instruments(
        defaultAssets.take(2).toList(),
        'USD',
      );
      final a = <Quote>[];
      final b = <Quote>[];
      final subA = source.quoteStream([instruments[0]]).listen(a.add);
      final subB = source.quoteStream([instruments[1]]).listen(b.add);
      async.elapse(const Duration(milliseconds: 1));

      expect(
        adapter.requests,
        hasLength(1),
        reason: 'one request for both rows',
      );
      expect(
        adapter.requests.single.uri.queryParameters['ids'],
        'bitcoin,ethereum',
      );
      expect(a.single.instrument.symbol, 'bitcoin');
      expect(b.single.instrument.symbol, 'ethereum');

      async.elapse(const Duration(seconds: 60));
      expect(adapter.requests, hasLength(2));

      subA.cancel();
      async.elapse(const Duration(seconds: 60));
      expect(adapter.requests, hasLength(3));
      expect(adapter.requests.last.uri.queryParameters['ids'], 'ethereum');
      expect(source.polledInstruments, {instruments[1]});

      subB.cancel();
      async.elapse(const Duration(minutes: 5));
      expect(
        adapter.requests,
        hasLength(3),
        reason: 'polling stops with the last listener',
      );
    });
  });

  test('quoteStream forwards errors and keeps polling', () {
    fakeAsync((async) {
      final adapter = FakeHttpAdapter(
        (_, i) => i == 0
            ? const FakeResponse(429, '{}')
            : FakeResponse(200, _fixture('simple_price.json')),
      );
      final source = build(adapter);
      final errors = <Object>[];
      final received = <Quote>[];
      source
          .quoteStream(source.instruments([btc], 'USD'))
          .listen(received.add, onError: errors.add);

      async.elapse(const Duration(milliseconds: 1));
      expect(errors.single, isA<QuotaExhausted>());
      async.elapse(const Duration(seconds: 60));
      expect(received, hasLength(1));
    });
  });

  test('book and tape streams are empty in prices-only mode', () {
    final source = build(
      FakeHttpAdapter((_, _) => const FakeResponse(200, '{}')),
    );
    final instrument = source.instrumentFor(btc, 'USD')!;
    expect(source.orderBookStream(instrument), emitsDone);
    expect(source.tradeStream(instrument), emitsDone);
  });
}
