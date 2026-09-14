import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The cases a cross-review found: each one a number the engine got
/// wrong once.
void main() {
  group('grid', () {
    test(
      'a sell placed onto a level that already holds one keeps both lots',
      () {
        // Two levels, entry between them, one unit per level: the start-up
        // buy backs a sell at 110; the buy at 90 places a second lot there.
        final params = GridParams(
          lower: d('90'),
          upper: d('110'),
          levels: 2,
          investment: d('190'),
          feeRate: Decimal.zero,
        );
        final r = runGrid([c(0, '100', '110', '90', '110')], params);

        final sells = r.trades.where((t) => t.side == TradeSide.sell).toList();
        expect(sells, hasLength(2));
        expect(sells.map((t) => t.realizedPnl), [d('10'), d('20')]);
        expect(r.baseHeld, Decimal.zero);
      },
    );

    test(
      'an order resting exactly at the open fills before the candle moves',
      () {
        final params = GridParams(
          lower: d('90'),
          upper: d('110'),
          levels: 5,
          investment: d('1000'),
          feeRate: Decimal.zero,
        );
        final r = runGrid([
          c(0, '100', '100', '96', '96'), // nothing filled yet: 95 not reached
          c(1, '95', '100', '95', '100'), // opens on the buy, rises past 100
        ], params);

        final sides = r.trades.map((t) => '${t.side.name}@${t.price}').toList();
        expect(sides, ['buy@100', 'buy@95', 'sell@100']);
      },
    );

    test(
      'a buy the quote cannot pay for stays resting; nothing is borrowed',
      () {
        // Three levels a cent apart with a fee: a losing round trip leaves
        // less than a re-buy costs.
        final params = GridParams(
          lower: d('99.99'),
          upper: d('100.01'),
          levels: 3,
          investment: d('200.18999'),
          feeRate: d('0.001'),
        );
        final r = runGrid([
          c(0, '100', '100', '99.99', '99.99'),
          c(1, '99.99', '100', '99.99', '100'),
          c(2, '100', '100', '99.99', '99.99'),
          c(3, '99.99', '100', '99.99', '100'),
        ], params);

        expect(r.quoteHeld, greaterThanOrEqualTo(Decimal.zero));
        for (final point in r.equity) {
          expect(point.equity, greaterThan(Decimal.zero));
        }
      },
    );

    test('an entry outside the range starts no grid', () {
      final params = GridParams(
        lower: d('90'),
        upper: d('110'),
        levels: 3,
        investment: d('240'),
        feeRate: Decimal.zero,
      );
      final r = runGrid([c(0, '80', '120', '80', '120')], params);

      expect(r.trades, isEmpty);
      expect(r.finalEquity, d('240'));
      expect(r.maxDrawdown, Decimal.zero);
    });

    test('the top level is exactly the upper bound', () {
      final params = GridParams(
        lower: d('100'),
        upper: d('101'),
        levels: 4,
        investment: d('1'),
        feeRate: Decimal.zero,
      );
      expect(params.prices.last, d('101'));
      expect(params.prices.first, d('100'));
      expect(params.prices, hasLength(4));
    });
  });

  group('dca', () {
    test(
      'several take-profits on one rising leg, each round opening at the last',
      () {
        final params = DcaParams(
          baseOrder: d('100'),
          safetyOrder: d('100'),
          safetyOrders: 0,
          stepPct: d('10'),
          takeProfitPct: d('5'),
          feeRate: Decimal.zero,
        );
        final r = runDca([c(0, '100', '120', '100', '120')], params);

        final prices = r.trades
            .map((t) => '${t.side.name}@${t.price}')
            .toList();
        expect(prices, [
          'buy@100',
          'sell@105',
          'buy@105',
          'sell@110.25',
          'buy@110.25',
          'sell@115.7625',
          'buy@115.7625',
        ]);
        expect(r.closedRoundTrips, 3);
      },
    );

    test('the take-profit nets the stated percent after both fees', () {
      // 101 quote at 1 % buys exactly one unit for 101 all in.
      final params = DcaParams(
        baseOrder: d('101'),
        safetyOrder: d('1'),
        safetyOrders: 0,
        stepPct: d('10'),
        takeProfitPct: d('5'),
        feeRate: d('0.01'),
      );
      final r = runDca([
        c(0, '100', '100', '100', '100'),
        c(1, '100', '120', '100', '120'),
      ], params);
      final sell = r.trades.firstWhere((t) => t.side == TradeSide.sell);

      expect(sell.qty, Decimal.one);
      // 5 % of the 101 the round cost.
      expect((sell.realizedPnl! - d('5.05')).abs(), lessThan(d('0.0001')));
    });

    test('tiny prices keep a take-profit above zero', () {
      final params = DcaParams(
        baseOrder: d('100'),
        safetyOrder: d('100'),
        safetyOrders: 1,
        stepPct: d('10'),
        takeProfitPct: d('5'),
        feeRate: Decimal.zero,
      );
      final r = runDca([
        c(0, '0.000000009', '0.000000009', '0.0000000081', '0.0000000081'),
        c(1, '0.0000000081', '0.00000001', '0.0000000081', '0.00000001'),
      ], params);

      // The rebound crosses several take-profits; every one is above zero.
      final sells = r.trades.where((t) => t.side == TradeSide.sell);
      expect(sells, isNotEmpty);
      for (final s in sells) {
        expect(s.price, greaterThan(Decimal.zero));
        expect(s.realizedPnl, greaterThan(Decimal.zero));
      }
    });

    test(
      'a losing round shrinks the next one to what is left; never negative',
      () {
        // No take-profit ever: everything is spent on the way down, then the
        // price crashes and a rebound closes at a loss? It cannot — the
        // take-profit is above cost. So a loss comes from the mark only, and
        // quote can never go below zero.
        final params = DcaParams(
          baseOrder: d('100'),
          safetyOrder: d('100'),
          safetyOrders: 3,
          stepPct: d('10'),
          takeProfitPct: d('1'),
          feeRate: d('0.001'),
          volumeMultiplier: d('2'),
        );
        final r = runDca([
          c(0, '100', '100', '50', '50'),
          c(1, '50', '200', '50', '200'),
          c(2, '200', '200', '100', '100'),
        ], params);

        expect(r.quoteHeld, greaterThanOrEqualTo(Decimal.zero));
        expect(r.trades.every((t) => t.qty > Decimal.zero), isTrue);
      },
    );

    test('digits stay bounded over many rounds', () {
      final params = DcaParams(
        baseOrder: d('100'),
        safetyOrder: d('1'),
        safetyOrders: 0,
        stepPct: d('10'),
        takeProfitPct: d('0.1'),
        feeRate: Decimal.zero,
      );
      // One long rise: a thousand take-profits on a single leg.
      final r = runDca([c(0, '100', '300', '100', '300')], params);

      expect(r.closedRoundTrips, greaterThan(900));
      for (final t in r.trades) {
        expect(t.price.scale, lessThanOrEqualTo(Money.priceScale));
        expect(t.qty.scale, lessThanOrEqualTo(Money.qtyScale));
      }
    });
  });

  group('second pass', () {
    test('a quantity rounds down, so nothing is bought on credit', () {
      final params = DcaParams(
        baseOrder: d('100'),
        safetyOrder: d('1'),
        safetyOrders: 0,
        stepPct: d('10'),
        takeProfitPct: d('5'),
        feeRate: Decimal.zero,
      );
      final r = runDca([c(0, '2048', '2048', '2048', '2048')], params);

      expect(r.trades.single.qty, d('0.04882812'));
      expect(r.quoteHeld, greaterThanOrEqualTo(Decimal.zero));
    });

    test('a take-profit that rounds onto its own entry does not spin', () {
      final params = DcaParams(
        baseOrder: d('100'),
        safetyOrder: d('1'),
        safetyOrders: 0,
        stepPct: d('10'),
        takeProfitPct: d('0.01'),
        feeRate: Decimal.zero,
      );
      final r = runDca([
        c(0, '0.000000001', '0.000000001', '0.000000001', '0.000000001'),
        c(1, '0.000000001', '0.000000002', '0.000000001', '0.000000002'),
      ], params);

      // A round per smallest price step at most — a thousand here, each
      // a real sale above its entry — and then the leg is done.
      expect(r.closedRoundTrips, inInclusiveRange(1, 1000));
      for (final t in r.trades.where((t) => t.realizedPnl != null)) {
        expect(t.realizedPnl, greaterThan(Decimal.zero));
      }
    });

    test(
      'too little for one unit per level: no grid, no zero-sized trades',
      () {
        final params = GridParams(
          lower: d('1000000000'),
          upper: d('2000000000'),
          levels: 2,
          investment: d('1'),
          feeRate: Decimal.zero,
        );
        final r = runGrid([
          c(0, '1000000000', '2000000000', '1000000000', '2000000000'),
        ], params);

        expect(r.trades, isEmpty);
        expect(r.closedRoundTrips, 0);
      },
    );

    test('the realized figure is exact: cost as paid, not rounded', () {
      final params = DcaParams(
        baseOrder: d('0.00123456789012'),
        safetyOrder: d('1'),
        safetyOrders: 0,
        stepPct: d('10'),
        takeProfitPct: d('5'),
        feeRate: Decimal.zero,
      );
      final r = runDca([
        c(
          0,
          '0.123456789012',
          '0.123456789012',
          '0.123456789012',
          '0.123456789012',
        ),
        c(1, '0.123456789012', '0.2', '0.123456789012', '0.2'),
      ], params);
      final buy = r.trades.first;
      final sell = r.trades.firstWhere((t) => t.side == TradeSide.sell);

      expect(sell.realizedPnl, sell.value - buy.value);
    });
  });
}
