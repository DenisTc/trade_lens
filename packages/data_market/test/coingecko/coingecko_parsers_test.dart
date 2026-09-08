import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/coingecko/$name').readAsStringSync());

const _btc = Instrument(
  sourceId: 'coingecko',
  symbol: 'bitcoin',
  base: Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin'),
  quote: 'USD',
);
const _eth = Instrument(
  sourceId: 'coingecko',
  symbol: 'ethereum',
  base: Asset(id: 'eth', symbol: 'ETH', name: 'Ethereum'),
  quote: 'USD',
);
const _unknown = Instrument(
  sourceId: 'coingecko',
  symbol: 'no-such-coin',
  base: Asset(id: 'zzz', symbol: 'ZZZ', name: 'Nope'),
  quote: 'USD',
);

void main() {
  final at = DateTime.utc(2026, 9, 8, 12);

  group('decimalFromJsonNumber', () {
    test('goes through the shortest string, not double arithmetic', () {
      expect(decimalFromJsonNumber(77718, 'usd'), Decimal.parse('77718'));
      expect(
        decimalFromJsonNumber(-2.0710415912101428, 'c'),
        Decimal.parse('-2.0710415912101428'),
      );
      expect(decimalFromJsonNumber(1e-7, 'tiny'), Decimal.parse('0.0000001'));
    });

    test('rejects strings', () {
      expect(() => decimalFromJsonNumber('1', 'x'), throwsFormatException);
    });
  });

  group('parseSimplePrice', () {
    test('maps every requested id and skips unknown ones', () {
      final json = _fixture('simple_price.json')! as Map<String, Object?>;
      final quotes = parseSimplePrice(json, [_btc, _eth, _unknown], at: at);

      expect(quotes.map((q) => q.instrument), [_btc, _eth]);
      final btc = json['bitcoin']! as Map<String, Object?>;
      expect(quotes.first.price, decimalFromJsonNumber(btc['usd'], 'usd'));
      expect(quotes.first.change24hPct, isNotNull);
      expect(quotes.first.at, at);
    });

    test('tolerates a missing 24h change', () {
      final quotes = parseSimplePrice(
        {
          'bitcoin': {'usd': 1},
        },
        [_btc],
        at: at,
      );
      expect(quotes.single.change24hPct, isNull);
    });
  });

  group('ohlcGranularity', () {
    test('follows the documented buckets', () {
      expect(ohlcGranularity(1), const Duration(minutes: 30));
      expect(ohlcGranularity(2), const Duration(minutes: 30));
      expect(ohlcGranularity(7), const Duration(hours: 4));
      expect(ohlcGranularity(30), const Duration(hours: 4));
      expect(ohlcGranularity(90), const Duration(days: 4));
    });
  });

  group('parseOhlc', () {
    test('shifts close timestamps back to openTime and has no volume', () {
      final rows = _fixture('ohlc_1d.json')! as List<Object?>;
      final candles = parseOhlc(rows, const Duration(minutes: 30));

      final firstClose = (rows.first! as List<Object?>)[0]! as num;
      expect(
        candles.first.openTime,
        DateTime.fromMillisecondsSinceEpoch(
          firstClose.toInt(),
          isUtc: true,
        ).subtract(const Duration(minutes: 30)),
      );
      expect(candles.first.volume, isNull);
      expect(
        candles[1].openTime.difference(candles[0].openTime),
        const Duration(minutes: 30),
      );
    });

    test('rejects malformed rows', () {
      expect(
        () => parseOhlc([
          [1, 2],
        ], const Duration(minutes: 30)),
        throwsFormatException,
      );
    });
  });
}
