import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(int minute, {String close = '10'}) => Candle(
  openTime: DateTime.utc(2026, 9, 9, 12, minute),
  open: Decimal.parse('10'),
  high: Decimal.parse('11'),
  low: Decimal.parse('9'),
  close: Decimal.parse(close),
  volume: Decimal.one,
);

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ProviderContainer container(FakeMarketDataSource source) {
    final c = ProviderContainer(
      retry: noRetry,
      overrides: fakeOverrides(source: source),
    );
    addTearDown(c.dispose);
    return c;
  }

  test('candles: history then live upserts', () async {
    final source = FakeMarketDataSource(history: [_c(0), _c(1)]);
    final c = container(source);
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    final states = <AsyncValue<List<Candle>>>[];
    c.listen(candlesProvider(btc, Interval.m1), (_, next) => states.add(next));
    await settle();
    expect(c.read(candlesProvider(btc, Interval.m1)).value, hasLength(2));
    expect(source.klineRequests.single, (btc, Interval.m1));

    source.emitCandle(btc, _c(1, close: '15'));
    await settle();
    expect(
      c.read(candlesProvider(btc, Interval.m1)).value!.last.close,
      Decimal.parse('15'),
    );

    source.emitCandle(btc, _c(2));
    await settle();
    expect(c.read(candlesProvider(btc, Interval.m1)).value, hasLength(3));
  });

  test(
    'candles: no stream subscription when the source cannot stream',
    () async {
      final source = FakeMarketDataSource(
        capabilities: Capabilities.pricesOnly,
        history: [_c(0)],
      );
      final c = container(source);
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      c.listen(candlesProvider(btc, Interval.auto), (_, _) {});
      await settle();
      source.emitCandle(btc, _c(1));
      await settle();
      expect(c.read(candlesProvider(btc, Interval.auto)).value, hasLength(1));
    },
  );

  test(
    'candles: cache is shown first, network replaces it and refills the cache',
    () async {
      final source = FakeMarketDataSource(history: [_c(0), _c(1), _c(2)]);
      final cache = FakeCandleCache();
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      await cache.write(btc, Interval.m1, [_c(0)]);
      final c = ProviderContainer(
        retry: noRetry,
        overrides: fakeOverrides(source: source, candleCache: cache),
      );
      addTearDown(c.dispose);
      final seen = <int>[];
      c.listen(candlesProvider(btc, Interval.m1), (_, next) {
        if (next.value case final v?) seen.add(v.length);
      });
      await settle();
      await settle();
      await settle();
      expect(seen.first, 1, reason: 'cached window shown first');
      expect(seen.last, 3, reason: 'network replaced it');
      expect(
        cache.entries.values.single,
        hasLength(3),
        reason: 'cache refilled',
      );
    },
  );

  test(
    'candles: with a cache, a REST failure keeps the cached window',
    () async {
      final source = FakeMarketDataSource(
        klinesError: const MarketError.unavailable(
          sourceId: 'fake',
          reason: 'timeout',
        ),
      );
      final cache = FakeCandleCache();
      final btc = source.instrumentFor(defaultAssets.first, 'USDT');
      await cache.write(btc, Interval.m1, [_c(0), _c(1)]);
      final c = ProviderContainer(
        retry: noRetry,
        overrides: fakeOverrides(source: source, candleCache: cache),
      );
      addTearDown(c.dispose);
      c.listen(candlesProvider(btc, Interval.m1), (_, _) {});
      await settle();
      await settle();
      await settle();
      final state = c.read(candlesProvider(btc, Interval.m1));
      expect(state.hasError, isFalse);
      expect(state.value, hasLength(2));
    },
  );

  test('candles: REST failure is an AsyncError', () async {
    final source = FakeMarketDataSource(
      klinesError: const MarketError.unavailable(
        sourceId: 'fake',
        reason: 'timeout',
      ),
    );
    final c = container(source);
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    c.listen(candlesProvider(btc, Interval.m1), (_, _) {});
    await settle();
    expect(c.read(candlesProvider(btc, Interval.m1)).hasError, isTrue);
  });

  test('selected interval defaults to 1h for full sources and auto for prices-only', () async {
    final full = container(FakeMarketDataSource())
      ..listen(selectedIntervalProvider, (_, _) {});
    await full.read(marketDataSourceProvider.future);
    await settle();
    expect(full.read(selectedIntervalProvider), Interval.h1);

    final rest = container(
      FakeMarketDataSource(capabilities: Capabilities.pricesOnly),
    )..listen(selectedIntervalProvider, (_, _) {});
    await rest.read(marketDataSourceProvider.future);
    await settle();
    expect(rest.read(selectedIntervalProvider), Interval.auto);
  });

  test('recentTrades keeps the newest 30, newest first', () async {
    final source = FakeMarketDataSource();
    final c = container(source);
    final btc = source.instrumentFor(defaultAssets.first, 'USDT');
    c.listen(recentTradesProvider(btc), (_, _) {});
    await settle();
    for (var i = 0; i < 40; i++) {
      source.emitTrade(
        btc,
        Trade(
          instrument: btc,
          id: '$i',
          price: Decimal.one,
          qty: Decimal.one,
          at: DateTime.utc(2026),
          isBuyerMaker: false,
        ),
      );
    }
    await settle();
    final trades = c.read(recentTradesProvider(btc)).value!;
    expect(trades, hasLength(recentTradesLimit));
    expect(trades.first.id, '39');
  });
}
