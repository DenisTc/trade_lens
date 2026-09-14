import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:ws_client/testing.dart';
import 'package:ws_client/ws_client.dart';

import '../support/fake_http_adapter.dart';

void main() {
  final btc = defaultAssets.first;
  final eth = defaultAssets[1];

  ({
    BybitMarketDataSource source,
    FakeTransport transport,
    FakeHttpAdapter http,
  })
  build({FakeResponse Function(int call)? rest}) {
    final transport = FakeTransport();
    final http = FakeHttpAdapter(
      (_, i) =>
          rest?.call(i) ??
          const FakeResponse(
            200,
            '{"retCode":0,"retMsg":"OK","result":{"list":[]}}',
          ),
    );
    final ws = WsClient(
      transport: transport,
      url: BybitHosts.ws,
      heartbeatStream: bybitTickerTopic('BTCUSDT'),
      protocol: const BybitWsProtocol(),
      backoff: Backoff(random: NoJitter()),
    );
    final source = BybitMarketDataSource(
      client: BybitRestClient(
        dio: createDio(baseUrl: BybitHosts.rest, adapter: http),
      ),
      ws: ws,
    );
    return (source: source, transport: transport, http: http);
  }

  Map<String, Object?> ticker(String symbol, String price) => {
    'topic': 'tickers.$symbol',
    'ts': 1789125875277,
    'type': 'snapshot',
    'data': {'symbol': symbol, 'lastPrice': price, 'price24hPcnt': '-0.0151'},
  };

  test("quoteStream subscribes with Bybit's op/args and maps tickers", () {
    fakeAsync((async) {
      final env = build();
      final quotes = <Quote>[];
      env.source
          .quoteStream(env.source.instruments([btc, eth], 'USDT'))
          .listen(quotes.add);
      async.elapse(const Duration(seconds: 1));

      final command = env.transport.last.commands.single;
      expect(command['op'], 'subscribe');
      expect(command['args'], ['tickers.BTCUSDT', 'tickers.ETHUSDT']);

      env.transport.last.push(ticker('ETHUSDT', '4000.5'));
      async.flushMicrotasks();
      expect(quotes.single.instrument.symbol, 'ETHUSDT');
      expect(quotes.single.price, Decimal.parse('4000.5'));
      expect(quotes.single.change24hPct, Decimal.parse('-1.51'));
      expect(
        quotes.single.at,
        DateTime.fromMillisecondsSinceEpoch(1789125875277, isUtc: true),
      );
    });
  });

  test('the client pings every 20 s, and a pong is not data', () {
    fakeAsync((async) {
      final env = build();
      env.source
          .quoteStream(env.source.instruments([btc], 'USDT'))
          .listen((_) {});
      async.elapse(const Duration(seconds: 41));

      final ops = env.transport.last.commands.map((c) => c['op']).toList();
      expect(ops, ['subscribe', 'ping', 'ping']);

      env.transport.last.push({'op': 'pong', 'success': true});
      async.flushMicrotasks();
      expect(env.transport.last.closed, isFalse);
    });
  });

  test('klineStream flattens the data array', () {
    fakeAsync((async) {
      final env = build();
      final candles = <Candle>[];
      env.source
          .klineStream(env.source.instrumentFor(btc, 'USDT')!, Interval.h1)
          .listen(candles.add);
      async.elapse(const Duration(seconds: 1));

      // The heartbeat ticker rides along with every subscription.
      expect(env.transport.last.commands.single['args'], [
        'kline.60.BTCUSDT',
        'tickers.BTCUSDT',
      ]);
      env.transport.last.push({
        'topic': 'kline.60.BTCUSDT',
        'type': 'snapshot',
        'ts': 1,
        'data': [
          {
            'start': 1789124400000,
            'open': '1',
            'high': '2',
            'low': '0.5',
            'close': '1.5',
            'volume': '9',
          },
          {
            'start': 1789128000000,
            'open': '1.5',
            'high': '2',
            'low': '1',
            'close': '1.7',
            'volume': '3',
          },
        ],
      });
      async.flushMicrotasks();

      expect(candles.map((c) => '${c.close}'), ['1.5', '1.7']);
    });
  });

  test(
    'orderBookStream: snapshot, delta, then silence when a frame is lost',
    () {
      fakeAsync((async) {
        final env = build();
        final books = <OrderBookSnapshot>[];
        env.source
            .orderBookStream(env.source.instrumentFor(btc, 'USDT')!)
            .listen(books.add);
        async.elapse(const Duration(seconds: 1));
        expect(env.transport.last.commands.single['args'], [
          'orderbook.50.BTCUSDT',
          'tickers.BTCUSDT',
        ]);

        Map<String, Object?> frame(
          String type,
          int seq, {
          List<List<String>> b = const [],
          List<List<String>> a = const [],
        }) => {
          'topic': 'orderbook.50.BTCUSDT',
          'type': type,
          'ts': 1789125875796,
          'data': {'s': 'BTCUSDT', 'b': b, 'a': a, 'u': seq, 'seq': seq * 10},
        };

        env.transport.last
          ..push(
            frame(
              'snapshot',
              100,
              b: [
                ['100', '1'],
                ['99', '2'],
              ],
              a: [
                ['101', '1'],
              ],
            ),
          )
          ..push(
            frame(
              'delta',
              101,
              b: [
                ['99', '0'],
                ['100.5', '3'],
              ],
            ),
          )
          ..push(frame('delta', 101)) // repeated sequence: a lost frame
          ..push(
            frame(
              'delta',
              103,
              b: [
                ['98', '1'],
              ],
            ),
          ); // still refused
        async.flushMicrotasks();

        expect(books, hasLength(2));
        expect(books.last.bids.map((l) => '${l.price}'), ['100.5', '100']);

        env.transport.last
          ..push(
            frame(
              'snapshot',
              200,
              b: [
                ['50', '1'],
              ],
              a: [
                ['51', '1'],
              ],
            ),
          )
          ..push(
            frame(
              'delta',
              201,
              a: [
                ['51', '0'],
                ['52', '2'],
              ],
            ),
          );
        async.flushMicrotasks();
        expect(books, hasLength(4));
        expect(books.last.asks.single.price, Decimal.parse('52'));
      });
    },
  );

  test('tradeStream expands the data array', () {
    fakeAsync((async) {
      final env = build();
      final trades = <Trade>[];
      env.source
          .tradeStream(env.source.instrumentFor(btc, 'USDT')!)
          .listen(trades.add);
      async.elapse(const Duration(seconds: 1));

      env.transport.last.push({
        'topic': 'publicTrade.BTCUSDT',
        'type': 'snapshot',
        'ts': 2,
        'data': [
          {'i': '1', 'T': 1789125884063, 'p': '1', 'v': '0.1', 'S': 'Buy'},
          {'i': '2', 'T': 1789125884064, 'p': '1', 'v': '0.2', 'S': 'Sell'},
        ],
      });
      async.flushMicrotasks();

      expect(trades.map((t) => t.isBuyerMaker), [false, true]);
    });
  });

  test('a reconnect backfills one page from the last candle seen', () {
    fakeAsync((async) {
      final calls = <int>[];
      final env = build(
        rest: (i) {
          calls.add(i);
          return FakeResponse(
            200,
            jsonEncode({
              'retCode': 0,
              'retMsg': 'OK',
              'result': {
                'list': [
                  ['1789131600000', '1', '2', '0.5', '1.9', '1', '1'],
                  ['1789128000000', '1', '2', '0.5', '1.8', '1', '1'],
                  ['1789124400000', '1', '2', '0.5', '1.5', '1', '1'],
                ],
              },
            }),
          );
        },
      );
      final candles = <Candle>[];
      env.source
          .klineStream(env.source.instrumentFor(btc, 'USDT')!, Interval.h1)
          .listen(candles.add);
      async.elapse(const Duration(seconds: 1));
      env.transport.last.push({
        'topic': 'kline.60.BTCUSDT',
        'type': 'snapshot',
        'ts': 1,
        'data': [
          {
            'start': 1789128000000,
            'open': '1',
            'high': '2',
            'low': '0.5',
            'close': '1.6',
            'volume': '9',
          },
        ],
      });
      async.flushMicrotasks();

      env.transport.last.drop();
      async
        ..elapse(const Duration(seconds: 2))
        ..flushMicrotasks();

      expect(calls, hasLength(1), reason: 'one backfill page');
      // Candles from the last seen open time onwards; the older one is not.
      expect(candles.map((c) => '${c.close}'), ['1.6', '1.8', '1.9']);
    });
  });

  test('a listener that arrives while the book is still held gets it', () {
    fakeAsync((async) {
      final env = build();
      final instrument = env.source.instrumentFor(btc, 'USDT')!;
      final first = env.source.orderBookStream(instrument).listen((_) {});
      async.elapse(const Duration(seconds: 1));
      env.transport.last.push({
        'topic': 'orderbook.50.BTCUSDT',
        'type': 'snapshot',
        'ts': 1,
        'data': {
          's': 'BTCUSDT',
          'b': [
            ['100', '1'],
          ],
          'a': [
            ['101', '1'],
          ],
          'u': 5,
          'seq': 1,
        },
      });
      async.flushMicrotasks();

      // Leaves, and another opens the pair within the unsubscribe grace.
      unawaited(first.cancel());
      async.elapse(const Duration(milliseconds: 500));
      final books = <OrderBookSnapshot>[];
      env.source.orderBookStream(instrument).listen(books.add);
      async.flushMicrotasks();
      expect(books, hasLength(1), reason: 'the held book is delivered at once');

      env.transport.last.push({
        'topic': 'orderbook.50.BTCUSDT',
        'type': 'delta',
        'ts': 2,
        'data': {
          's': 'BTCUSDT',
          'b': [
            ['100.5', '2'],
          ],
          'a': <List<String>>[],
          'u': 6,
          'seq': 2,
        },
      });
      async.flushMicrotasks();
      expect(books, hasLength(2));
      expect(books.last.bids.first.price, Decimal.parse('100.5'));
    });
  });

  test('an unreadable book frame asks the exchange for a fresh snapshot', () {
    fakeAsync((async) {
      final env = build();
      final instrument = env.source.instrumentFor(btc, 'USDT')!;
      final books = <OrderBookSnapshot>[];
      final errors = <Object>[];
      env.source
          .orderBookStream(instrument)
          .listen(books.add, onError: errors.add);
      async.elapse(const Duration(seconds: 1));
      env.transport.last
        ..push({
          'topic': 'orderbook.50.BTCUSDT',
          'type': 'snapshot',
          'ts': 1,
          'data': {
            's': 'BTCUSDT',
            'b': [
              ['100', '1'],
            ],
            'a': [
              ['101', '1'],
            ],
            'u': 5,
          },
        })
        ..push({
          'topic': 'orderbook.50.BTCUSDT',
          'type': 'delta',
          'ts': 2,
          'data': {
            's': 'BTCUSDT',
            'b': [
              ['100', 'not a number'],
            ],
            'a': <List<String>>[],
            'u': 6,
          },
        })
        ..push({
          'topic': 'orderbook.50.BTCUSDT',
          'type': 'delta',
          'ts': 3,
          'data': {
            's': 'BTCUSDT',
            'b': [
              ['99', '1'],
            ],
            'a': <List<String>>[],
            'u': 7,
          },
        });
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));

      expect(errors, hasLength(1));
      // The delta after the bad one is not applied on a book it may have
      // corrupted; the topic is taken again instead.
      expect(books, hasLength(1));
      final ops = env.transport.last.commands.map((c) => c['op']).toList();
      expect(ops, ['subscribe', 'unsubscribe', 'subscribe']);
    });
  });

  test('a live candle during the backfill wins over the REST copy', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final transport = FakeTransport();
      final http = _GatedAdapter(
        gate.future,
        FakeHttpAdapter(
          (_, _) => FakeResponse(
            200,
            jsonEncode({
              'retCode': 0,
              'retMsg': 'OK',
              'result': {
                'list': [
                  ['1789128000000', '1', '2', '0.5', '1.8', '1', '1'],
                ],
              },
            }),
          ),
        ),
      );
      final source = BybitMarketDataSource(
        client: BybitRestClient(
          dio: createDio(baseUrl: BybitHosts.rest, adapter: http),
        ),
        ws: WsClient(
          transport: transport,
          url: BybitHosts.ws,
          protocol: const BybitWsProtocol(),
          backoff: Backoff(random: NoJitter()),
        ),
      );
      final candles = <Candle>[];
      source
          .klineStream(source.instrumentFor(btc, 'USDT')!, Interval.h1)
          .listen(candles.add);
      async.elapse(const Duration(seconds: 1));
      Map<String, Object?> live(String close) => {
        'topic': 'kline.60.BTCUSDT',
        'type': 'snapshot',
        'ts': 1,
        'data': [
          {
            'start': 1789128000000,
            'open': '1',
            'high': '2',
            'low': '0.5',
            'close': close,
            'volume': '9',
          },
        ],
      };
      transport.last.push(live('1.6'));
      async.flushMicrotasks();

      transport.last.drop();
      async.elapse(const Duration(seconds: 1)); // reconnected, REST pending
      transport.last.push(live('2.1')); // newer than what REST will say
      async.flushMicrotasks();
      expect(candles, hasLength(1), reason: 'buffered while the backfill runs');

      gate.complete();
      async.elapse(const Duration(milliseconds: 100));
      expect(candles.map((c) => '${c.close}'), ['1.6', '2.1']);
    });
  });

  test('a long outage is paged back to the last candle seen', () {
    fakeAsync((async) {
      final ends = <String?>[];
      final env = build(
        rest: (i) {
          ends.add(null);
          // Page 0: the newest two; page 1: the two before them.
          final rows = i == 0
              ? [
                  ['1789135200000', '1', '2', '0.5', '1.4', '1', '1'],
                  ['1789131600000', '1', '2', '0.5', '1.3', '1', '1'],
                ]
              : [
                  ['1789128000000', '1', '2', '0.5', '1.2', '1', '1'],
                  ['1789124400000', '1', '2', '0.5', '1.1', '1', '1'],
                ];
          return FakeResponse(
            200,
            jsonEncode({
              'retCode': 0,
              'retMsg': 'OK',
              'result': {'list': rows},
            }),
          );
        },
      );
      final source = BybitMarketDataSource(
        client: BybitRestClient(
          dio: createDio(baseUrl: BybitHosts.rest, adapter: env.http),
        ),
        ws: WsClient(
          transport: env.transport,
          url: BybitHosts.ws,
          protocol: const BybitWsProtocol(),
          backoff: Backoff(random: NoJitter()),
        ),
        backfillPageSize: 2,
      );
      final candles = <Candle>[];
      source
          .klineStream(source.instrumentFor(btc, 'USDT')!, Interval.h1)
          .listen(candles.add);
      async.elapse(const Duration(seconds: 1));
      env.transport.last.push({
        'topic': 'kline.60.BTCUSDT',
        'type': 'snapshot',
        'ts': 1,
        'data': [
          {
            'start': 1789128000000,
            'open': '1',
            'high': '2',
            'low': '0.5',
            'close': '1.0',
            'volume': '9',
          },
        ],
      });
      async.flushMicrotasks();
      env.transport.last.drop();
      async
        ..elapse(const Duration(seconds: 2))
        ..flushMicrotasks();

      expect(ends, hasLength(2), reason: 'two pages to reach the last candle');
      expect(candles.map((c) => '${c.close}'), ['1', '1.2', '1.3', '1.4']);
    });
  });
}

/// Holds every answer until [gate] completes: a REST call in flight.
final class _GatedAdapter implements HttpClientAdapter {
  _GatedAdapter(this.gate, this.inner);

  final Future<void> gate;
  final HttpClientAdapter inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => gate.then((_) => inner.fetch(options, requestStream, cancelFuture));

  @override
  void close({bool force = false}) => inner.close(force: force);
}
