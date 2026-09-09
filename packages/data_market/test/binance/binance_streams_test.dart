import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

Map<String, Object?> _data(String name) {
  final frame = jsonDecode(
    File('test/fixtures/binance/ws/$name').readAsStringSync(),
  ) as Map<String, Object?>;
  return frame['data']! as Map<String, Object?>;
}

const _btc = Instrument(
  sourceId: 'binance',
  symbol: 'BTCUSDT',
  base: Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin'),
  quote: 'USDT',
);

void main() {
  test('stream names are lowercase with the documented suffixes', () {
    expect(miniTickerStreamName('BTCUSDT'), 'btcusdt@miniTicker');
    expect(klineStreamName('BTCUSDT', Interval.m15), 'btcusdt@kline_15m');
    expect(depth10StreamName('BTCUSDT'), 'btcusdt@depth10@100ms');
    expect(tradeStreamName('BTCUSDT'), 'btcusdt@trade');
  });

  test('parseMiniTicker derives the 24h change from close and open', () {
    final data = _data('miniTicker.json');
    final quote = parseMiniTicker(data, _btc);

    final close = Decimal.parse(data['c']! as String);
    final open = Decimal.parse(data['o']! as String);
    expect(quote.price, close);
    final expected = ((close - open) * Decimal.fromInt(100) / open).toDecimal(
      scaleOnInfinitePrecision: 3,
    );
    expect(quote.change24hPct, expected);
    expect(quote.at.millisecondsSinceEpoch, data['E']);
  });

  test('parseMiniTicker returns null change when open is zero', () {
    final quote = parseMiniTicker({'c': '1', 'o': '0', 'E': 1}, _btc);
    expect(quote.change24hPct, isNull);
  });

  test('parseDepth10 maps ten levels per side, best first', () {
    final at = DateTime.utc(2026, 9, 8);
    final book = parseDepth10(_data('depth10_100ms.json'), _btc, at: at);

    expect(book.bids, hasLength(10));
    expect(book.asks, hasLength(10));
    expect(book.bids.first.price > book.bids.last.price, isTrue);
    expect(book.asks.first.price < book.asks.last.price, isTrue);
    expect(book.bids.first.price < book.asks.first.price, isTrue);
    expect(book.at, at);
  });

  test('parseTradeEvent maps id, side and time', () {
    final data = _data('trade.json');
    final trade = parseTradeEvent(data, _btc);
    expect(trade.id, '${data['t']}');
    expect(trade.price, Decimal.parse(data['p']! as String));
    expect(trade.qty, Decimal.parse(data['q']! as String));
    expect(trade.isBuyerMaker, data['m']);
    expect(trade.at.millisecondsSinceEpoch, data['T']);
  });

  test('parseKlineEvent maps the k object of the stream frame', () {
    final k = _data('kline_1m.json')['k']! as Map<String, Object?>;
    final candle = parseKlineEvent(k);
    expect(candle.openTime.millisecondsSinceEpoch, k['t']);
    expect(candle.close, Decimal.parse(k['c']! as String));
  });

  test('malformed payloads are FormatExceptions', () {
    expect(() => parseTradeEvent({'t': 'x'}, _btc), throwsFormatException);
    expect(
      () => parseDepth10({'bids': 'x', 'asks': []}, _btc, at: DateTime(0)),
      throwsFormatException,
    );
    expect(
      () => parseMiniTicker({'c': 1, 'o': '1', 'E': 1}, _btc),
      throwsFormatException,
    );
  });
}
