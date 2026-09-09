import 'dart:async';

import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  final btc = defaultAssets.first;
  final eth = defaultAssets[1];

  Position position(Asset asset, String qty, String price) => Position(
    id: '${asset.id}-USDT',
    asset: asset,
    quote: 'USDT',
    qty: Decimal.parse(qty),
    avgPrice: Decimal.parse(price),
    createdAt: DateTime.utc(2026, 9, 9),
  );

  test('live quotes value the portfolio and mark it live', () async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position(btc, '0.5', '60000'));
    final c = ProviderContainer(
      retry: noRetry,
      overrides: [
        ...fakeOverrides(source: source, portfolio: repo),
        connectionStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectionStatus.connected),
        ),
      ],
    );
    addTearDown(c.dispose);

    c.listen(portfolioValuationProvider, (_, _) {});
    await settle();
    await settle();
    source.emit(source.instrumentFor(btc, 'USDT'), '70000');
    await settle();
    await settle();

    final v = c.read(portfolioValuationProvider).value!;
    expect(v.isLive, isTrue);
    expect(v.totals.single.total, Decimal.parse('35000'));
    expect(v.totals.single.pnl, Decimal.parse('5000'));
  });

  test(
    'without a live quote the last stored quote is used, as of its time',
    () async {
      final source = FakeMarketDataSource();
      final repo = FakePortfolioRepository();
      await repo.upsert(position(btc, '1', '60000'));
      final store = FakeLastQuoteStore();
      final at = DateTime.utc(2026, 9, 9, 12, 40);
      await store.save(
        Quote(
          instrument: source.instrumentFor(btc, 'USDT'),
          price: Decimal.parse('65000'),
          change24hPct: null,
          at: at,
        ),
      );
      final c = ProviderContainer(
        retry: noRetry,
        overrides: fakeOverrides(
          source: source,
          portfolio: repo,
          lastQuotes: store,
        ),
      );
      addTearDown(c.dispose);

      c.listen(portfolioValuationProvider, (_, _) {});
      await settle();
      await settle();
      await settle();

      final v = c.read(portfolioValuationProvider).value!;
      expect(v.isLive, isFalse);
      expect(v.asOf, at);
      expect(v.totals.single.total, Decimal.parse('65000'));
    },
  );

  test('a position the source cannot price stays unavailable', () async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position(btc, '1', '1'));
    await repo.upsert(
      position(eth, '1', '1').copyWith(quote: 'EUR', id: 'eth-EUR'),
    );
    final c = ProviderContainer(
      retry: noRetry,
      overrides: fakeOverrides(source: source, portfolio: repo),
    );
    addTearDown(c.dispose);
    c.listen(portfolioValuationProvider, (_, _) {});
    await settle();
    await settle();
    source.emit(source.instrumentFor(btc, 'USDT'), '2');
    await settle();
    await settle();

    final v = c.read(portfolioValuationProvider).value!;
    expect(v.unavailableCount, 1);
    expect(v.entries.last.position.quote, 'EUR');
  });

  test(
    'quote provider persists quotes at most every 15 s per instrument',
    () async {
      final source = FakeMarketDataSource();
      final store = FakeLastQuoteStore();
      final c = ProviderContainer(
        retry: noRetry,
        overrides: fakeOverrides(source: source, lastQuotes: store),
      );
      addTearDown(c.dispose);
      final btcInstrument = source.instrumentFor(btc, 'USDT');
      var now = DateTime.utc(2026, 9, 9, 12);
      await withClock(Clock(() => now), () async {
        c.listen(quoteProvider(btcInstrument), (_, _) {});
        await settle();
        source.emit(btcInstrument, '1');
        await settle();
        source.emit(btcInstrument, '2');
        await settle();
        expect(
          store.saved.values.single.price,
          Decimal.one,
          reason: 'throttled',
        );
        now = now.add(const Duration(seconds: 16));
        source.emit(btcInstrument, '3');
        await settle();
        expect(store.saved.values.single.price, Decimal.fromInt(3));
      });
    },
  );

  test('a dropped socket turns the valuation into "as of"', () async {
    final source = FakeMarketDataSource();
    final repo = FakePortfolioRepository();
    await repo.upsert(position(btc, '1', '1'));
    final status = StreamController<ConnectionStatus>.broadcast();
    final c = ProviderContainer(
      retry: noRetry,
      overrides: [
        ...fakeOverrides(source: source, portfolio: repo),
        connectionStatusProvider.overrideWith((ref) => status.stream),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(status.close);
    c.listen(portfolioValuationProvider, (_, _) {});
    await settle();
    await settle();
    status.add(ConnectionStatus.connected);
    await settle();
    source.emit(source.instrumentFor(btc, 'USDT'), '2');
    await settle();
    await settle();
    expect(c.read(portfolioValuationProvider).value!.isLive, isTrue);

    status.add(ConnectionStatus.reconnecting);
    await settle();
    await settle();
    final v = c.read(portfolioValuationProvider).value!;
    expect(v.isLive, isFalse);
    expect(
      v.totals.single.total,
      Decimal.fromInt(2),
      reason: 'last price kept',
    );
  });

  test('commands add and remove positions', () async {
    final repo = FakePortfolioRepository();
    final c = ProviderContainer(
      retry: noRetry,
      overrides: fakeOverrides(source: FakeMarketDataSource(), portfolio: repo),
    );
    addTearDown(c.dispose);
    await c
        .read(portfolioCommandsProvider.notifier)
        .add(
          asset: btc,
          quote: 'USDT',
          qty: Decimal.one,
          avgPrice: Decimal.fromInt(5),
          note: 'n',
        );
    final stored = (await repo.positions()).single;
    expect(stored.note, 'n');
    await c.read(portfolioCommandsProvider.notifier).remove(stored.id);
    expect(await repo.positions(), isEmpty);
  });
}
