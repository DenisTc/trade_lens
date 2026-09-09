import 'dart:convert';
import 'dart:io';

import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:ws_client/testing.dart';
import 'package:ws_client/ws_client.dart';

import '../support/fake_http_adapter.dart';

Map<String, Object?> _frame(String name) =>
    jsonDecode(File('test/fixtures/binance/ws/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  final btc = defaultAssets.first;
  final eth = defaultAssets[1];

  ({
    BinanceMarketDataSource source,
    FakeTransport transport,
    FakeHttpAdapter http,
  })
  build({FakeResponse Function(RequestOptionsLike, int)? rest, int? pageSize}) {
    final transport = FakeTransport();
    final http = FakeHttpAdapter(
      (options, i) =>
          rest?.call((
            path: options.uri.path,
            query: options.uri.queryParameters,
          ), i) ??
          const FakeResponse(200, '[]'),
    );
    final ws = WsClient(
      transport: transport,
      url: BinanceHosts.global.ws,
      heartbeatStream: 'btcusdt@miniTicker',
      backoff: Backoff(random: NoJitter()),
    );
    final source = BinanceMarketDataSource(
      client: BinanceRestClient(
        dio: createDio(baseUrl: BinanceHosts.global.rest, adapter: http),
      ),
      hosts: BinanceHosts.global,
      ws: ws,
      backfillPageSize: pageSize ?? 500,
    );
    return (source: source, transport: transport, http: http);
  }

  test(
    'quoteStream subscribes one miniTicker per instrument and maps frames',
    () {
      fakeAsync((async) {
        final env = build();
        final source = env.source;
        final quotes = <Quote>[];
        source
            .quoteStream(source.instruments([btc, eth], 'USDT'))
            .listen(quotes.add);
        async.elapse(const Duration(seconds: 1));

        final command = env.transport.last.commands.single;
        expect((command['params']! as List).cast<String>(), [
          'btcusdt@miniTicker',
          'ethusdt@miniTicker',
        ]);

        env.transport.last.push(_frame('miniTicker.json'));
        async.flushMicrotasks();
        expect(quotes.single.instrument.symbol, 'BTCUSDT');
      });
    },
  );

  test('orderBookStream and tradeStream map their frames', () {
    fakeAsync((async) {
      final env = build();
      final instrument = env.source.instrumentFor(btc, 'USDT')!;
      final books = <OrderBookSnapshot>[];
      final trades = <Trade>[];
      env.source.orderBookStream(instrument).listen(books.add);
      env.source.tradeStream(instrument).listen(trades.add);
      async.elapse(const Duration(seconds: 1));

      env.transport.last
        ..push(_frame('depth10_100ms.json'))
        ..push(_frame('trade.json'));
      async.flushMicrotasks();

      expect(books.single.bids, hasLength(10));
      expect(trades.single.isBuyerMaker, isTrue);
    });
  });

  test('klineStream backfills from the last openTime after a reconnect', () {
    fakeAsync((async) {
      final klineFrame = _frame('kline_1m.json');
      final lastOpen = ((klineFrame['data']! as Map)['k']! as Map)['t']! as int;
      final restCalls = <Map<String, String>>[];
      final env = build(
        rest: (req, _) {
          restCalls.add(req.query);
          return FakeResponse(
            200,
            File('test/fixtures/binance/klines_1m.json').readAsStringSync(),
          );
        },
      );
      final instrument = env.source.instrumentFor(btc, 'USDT')!;
      final candles = <Candle>[];
      env.source.klineStream(instrument, Interval.m1).listen(candles.add);
      async.elapse(const Duration(seconds: 1));

      env.transport.last.push(klineFrame);
      async.flushMicrotasks();
      expect(candles, hasLength(1));
      expect(restCalls, isEmpty, reason: 'no backfill before any reconnect');

      env.transport.last.drop();
      async.elapse(const Duration(seconds: 2)); // reconnect + tick for Dio

      expect(restCalls.single['symbol'], 'BTCUSDT');
      expect(restCalls.single['interval'], '1m');
      expect(restCalls.single['startTime'], '$lastOpen');
      expect(candles, hasLength(1 + 3), reason: 'fixture has 3 candles');
    });
  });

  test(
    'backfill pages forward and emits history before buffered live candles',
    () {
      fakeAsync((async) {
        final klineFrame = _frame('kline_1m.json');
        final restCalls = <Map<String, String>>[];
        // Page size 3 makes the 3-row fixture a full page, so the source asks
        // for a second page, which comes back empty.
        final env = build(
          rest: (req, i) {
            restCalls.add(req.query);
            return FakeResponse(
              200,
              restCalls.length == 1
                  ? File('test/fixtures/binance/klines_1m.json')
                        .readAsStringSync()
                  : '[]',
            );
          },
          pageSize: 3,
        );
        final instrument = env.source.instrumentFor(btc, 'USDT')!;
        final candles = <Candle>[];
        env.source.klineStream(instrument, Interval.m1).listen(candles.add);
        async.elapse(const Duration(seconds: 1));
        env.transport.last.push(klineFrame);
        async.flushMicrotasks();

        env.transport.last.drop();
        async.elapse(const Duration(seconds: 2));

        expect(
          restCalls,
          hasLength(2),
          reason: 'full page → next page → empty',
        );
        final fixtureRows = jsonDecode(
          File('test/fixtures/binance/klines_1m.json').readAsStringSync(),
        ) as List<Object?>;
        final lastFixtureOpen = (fixtureRows.last! as List<Object?>)[0]! as int;
        expect(
          restCalls[1]['startTime'],
          '${lastFixtureOpen + 60000}',
          reason: 'second page starts one interval after the last row',
        );
        final times = candles.map((c) => c.openTime).toList();
        expect(
          times.skip(1).toList(),
          [...times.skip(1)]..sort(),
          reason: 'ordered after the live one',
        );
        expect(candles, hasLength(1 + 3));
      });
    },
  );

  test('source without a WsClient fails loudly on streams', () {
    final source = BinanceMarketDataSource(
      client: BinanceRestClient(
        dio: createDio(
          baseUrl: BinanceHosts.global.rest,
          adapter: FakeHttpAdapter((_, _) => const FakeResponse(200, '[]')),
        ),
      ),
      hosts: BinanceHosts.global,
    );
    expect(
      () => source.tradeStream(source.instrumentFor(btc, 'USDT')!),
      throwsStateError,
    );
  });
}

typedef RequestOptionsLike = ({String path, Map<String, String> query});
