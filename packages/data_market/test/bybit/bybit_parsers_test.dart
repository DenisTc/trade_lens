import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  final btc = Instrument(
    sourceId: 'bybit',
    symbol: 'BTCUSDT',
    base: defaultAssets.first,
    quote: 'USDT',
  );
  final at = DateTime.utc(2026, 9, 11, 12);

  test('interval codes: minutes as numbers, the day as D', () {
    expect(bybitIntervalCode(Interval.m1), '1');
    expect(bybitIntervalCode(Interval.m15), '15');
    expect(bybitIntervalCode(Interval.h1), '60');
    expect(bybitIntervalCode(Interval.d1), 'D');
    expect(() => bybitIntervalCode(Interval.auto), throwsArgumentError);
  });

  test('a REST kline row: strings throughout, including the open time', () {
    final candle = parseBybitKlineRow([
      '1789124400000',
      '76997.8',
      '76998.2',
      '76744.8',
      '76860.3',
      '157.5',
      '1',
    ]);

    expect(candle.openTime, DateTime.utc(2026, 9, 11, 11));
    expect(candle.open, Decimal.parse('76997.8'));
    expect(candle.close, Decimal.parse('76860.3'));
    expect(candle.volume, Decimal.parse('157.5'));
  });

  test('a kline frame element: the open time is a number this time', () {
    final candle = parseBybitKlineEvent({
      'start': 1789124400000,
      'open': '1',
      'high': '2',
      'low': '0.5',
      'close': '1.5',
      'volume': '9',
      'confirm': false,
    });

    expect(candle.openTime, DateTime.utc(2026, 9, 11, 11));
    expect(candle.close, Decimal.parse('1.5'));
  });

  test('a ticker: the 24h change is a fraction on the wire, percent here', () {
    final quote = parseBybitTicker(
      {'symbol': 'BTCUSDT', 'lastPrice': '76808.3', 'price24hPcnt': '-0.0152'},
      btc,
      at: at,
    );

    expect(quote.price, Decimal.parse('76808.3'));
    expect(quote.change24hPct, Decimal.parse('-1.52'));
    expect(quote.at, at);
  });

  test('a ticker without a change still carries the price', () {
    final quote = parseBybitTicker({'lastPrice': '1'}, btc, at: at);

    expect(quote.change24hPct, isNull);
  });

  test('a trade: the taker sold, so the buyer was the maker', () {
    final trade = parseBybitTrade({
      'i': '229',
      'T': 1789125884063,
      'p': '76822.4',
      'v': '0.000013',
      'S': 'Sell',
    }, btc);

    expect(trade.id, '229');
    expect(trade.isBuyerMaker, isTrue);
    expect(
      trade.at,
      DateTime.fromMillisecondsSinceEpoch(1789125884063, isUtc: true),
    );
  });

  test('malformed payloads are FormatExceptions, never TypeErrors', () {
    expect(() => parseBybitKlineRow('nope'), throwsFormatException);
    expect(() => parseBybitKlineRow(['1', '2']), throwsFormatException);
    expect(() => parseBybitKlineEvent({'start': 'x'}), throwsFormatException);
    expect(
      () => parseBybitTicker({'lastPrice': 1.5}, btc, at: at),
      throwsFormatException,
    );
    expect(
      () => parseBybitTrade({'i': 1, 'S': 'Buy'}, btc),
      throwsFormatException,
    );
    expect(
      () => parseBybitTrade({
        'i': '1',
        'S': 'Hold',
        'p': '1',
        'v': '1',
        'T': 1,
      }, btc),
      throwsFormatException,
    );
    expect(
      () => parseBybitLevels([
        ['1'],
      ], 'b'),
      throwsFormatException,
    );
    expect(() => parseBybitLevels('x', 'b'), throwsFormatException);
  });
}
