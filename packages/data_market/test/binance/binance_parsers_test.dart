import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/binance/$name').readAsStringSync());

const _btc = Instrument(
  sourceId: 'binance',
  symbol: 'BTCUSDT',
  base: Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin'),
  quote: 'USDT',
);

void main() {
  group('parseTicker24h', () {
    test('keeps the exchange decimal string exactly', () {
      final rows = (_fixture('ticker_24hr.json')! as List)
          .cast<Map<String, Object?>>();
      final btc = rows.firstWhere((r) => r['symbol'] == 'BTCUSDT');

      final quote = parseTicker24h(btc, _btc);

      expect(quote.instrument, _btc);
      expect(quote.price, Decimal.parse(btc['lastPrice']! as String));
      expect(
        quote.change24hPct,
        Decimal.parse(btc['priceChangePercent']! as String),
      );
      expect(quote.at.isUtc, isTrue);
      expect(quote.at.millisecondsSinceEpoch, btc['closeTime']);
    });

    test('rejects a numeric price', () {
      expect(
        () => parseTicker24h({
          'lastPrice': 1.5,
          'priceChangePercent': '1',
          'closeTime': 1,
        }, _btc),
        throwsFormatException,
      );
    });
  });

  group('parseKline', () {
    test('maps the positional row', () {
      final rows = (_fixture('klines_1m.json')! as List).cast<List<Object?>>();
      final candle = parseKline(rows.first);

      expect(candle.openTime.millisecondsSinceEpoch, rows.first[0]);
      expect(candle.open, Decimal.parse(rows.first[1]! as String));
      expect(candle.high, Decimal.parse(rows.first[2]! as String));
      expect(candle.low, Decimal.parse(rows.first[3]! as String));
      expect(candle.close, Decimal.parse(rows.first[4]! as String));
      expect(candle.volume, Decimal.parse(rows.first[5]! as String));
    });

    test('consecutive 1m candles are one minute apart', () {
      final rows = (_fixture('klines_1m.json')! as List).cast<List<Object?>>();
      final candles = rows.map(parseKline).toList();
      expect(
        candles[1].openTime.difference(candles[0].openTime),
        const Duration(minutes: 1),
      );
    });

    test('rejects a short row', () {
      expect(() => parseKline([1, '2', '3']), throwsFormatException);
    });
  });

  test('parseKlineEvent maps the stream payload', () {
    final candle = parseKlineEvent({
      't': 1788789600000,
      'o': '1.0',
      'h': '2.0',
      'l': '0.5',
      'c': '1.5',
      'v': '10',
    });
    expect(candle.close, Decimal.parse('1.5'));
    expect(candle.volume, Decimal.parse('10'));
  });
}
