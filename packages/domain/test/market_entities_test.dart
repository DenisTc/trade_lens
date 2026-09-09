import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('Interval', () {
    test('fixed intervals carry their duration and wire code', () {
      expect(Interval.m1.duration, const Duration(minutes: 1));
      expect(Interval.m15.duration, const Duration(minutes: 15));
      expect(Interval.h1.duration, const Duration(hours: 1));
      expect(Interval.d1.duration, const Duration(days: 1));
      expect(Interval.h1.code, '1h');
    });

    test('auto has no duration', () {
      expect(Interval.auto.duration, isNull);
    });
  });

  group('defaultAssets', () {
    test('has 20 assets with unique lowercase ids', () {
      expect(defaultAssets, hasLength(20));
      final ids = defaultAssets.map((a) => a.id).toSet();
      expect(ids, hasLength(20));
      for (final id in ids) {
        expect(id, id.toLowerCase());
      }
    });

    test('starts with BTC', () {
      expect(defaultAssets.first.symbol, 'BTC');
    });
  });

  group('Instrument', () {
    const btc = Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin');

    test('is equal by value so it can key family providers', () {
      const a = Instrument(
        sourceId: 'binance',
        symbol: 'BTCUSDT',
        base: btc,
        quote: 'USDT',
      );
      const b = Instrument(
        sourceId: 'binance',
        symbol: 'BTCUSDT',
        base: btc,
        quote: 'USDT',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.displayName, 'BTC/USDT');
    });

    test('differs by source', () {
      const a = Instrument(
        sourceId: 'binance',
        symbol: 'BTCUSDT',
        base: btc,
        quote: 'USDT',
      );
      const b = Instrument(
        sourceId: 'binance_us',
        symbol: 'BTCUSDT',
        base: btc,
        quote: 'USDT',
      );
      expect(a, isNot(b));
    });
  });

  group('Capabilities', () {
    test('pricesOnly hides book, tape, volume and intervals', () {
      expect(Capabilities.pricesOnly.orderBook, isFalse);
      expect(Capabilities.pricesOnly.intervals, {Interval.auto});
      expect(Capabilities.full.intervals, contains(Interval.m1));
    });
  });

  test('Quote keeps Decimal precision from exchange strings', () {
    final quote = Quote(
      instrument: const Instrument(
        sourceId: 'binance',
        symbol: 'BTCUSDT',
        base: Asset(id: 'btc', symbol: 'BTC', name: 'Bitcoin'),
        quote: 'USDT',
      ),
      price: Decimal.parse('77790.01000000'),
      change24hPct: Decimal.parse('-1.939'),
      at: DateTime.utc(2026, 9, 8),
    );
    expect(quote.price.toString(), '77790.01');
  });
}
