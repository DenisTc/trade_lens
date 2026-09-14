import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final params = DcaParams(
    baseOrder: d('100'),
    safetyOrder: d('100'),
    safetyOrders: 2,
    stepPct: d('10'),
    takeProfitPct: d('5'),
    feeRate: Decimal.zero,
  );

  test('capital is the base order plus every safety order', () {
    expect(params.capital, d('300'));
    final doubling = DcaParams(
      baseOrder: d('10'),
      safetyOrder: d('10'),
      safetyOrders: 3,
      stepPct: d('1'),
      takeProfitPct: d('1'),
      feeRate: Decimal.zero,
      volumeMultiplier: d('2'),
    );
    expect(doubling.capital, d('80')); // 10 + 10 + 20 + 40
  });

  test('a round: base order, take-profit, the next round opens there', () {
    final r = runDca([
      c(0, '100', '100', '100', '100'),
      c(1, '100', '106', '100', '106'),
    ], params);

    expect(r.trades.map((t) => t.side.name), ['buy', 'sell', 'buy']);
    expect(r.trades[1].price, d('105'));
    expect(r.trades[1].realizedPnl, d('5'));
    expect(r.closedRoundTrips, 1);
  });

  test('safety orders fill on the way down and lift the average', () {
    final r = runDca([
      c(0, '100', '100', '80', '80'), // safety at 90 and then 81
    ], params);

    expect(r.trades.map((t) => '${t.price}'), ['100', '90', '81']);
    // Quantities are rounded to eight places: dust may remain.
    expect(r.quoteHeld, lessThan(d('0.001')), reason: 'all three orders spent');
    // 300 quote for 1 + 1.11… + 1.2345… base: the average is below 100.
    final average = (d('300') / r.baseHeld).toDecimal(
      scaleOnInfinitePrecision: 4,
    );
    expect(average, lessThan(d('100')));
    expect((r.finalEquity - r.baseHeld * d('80')).abs(), lessThan(d('0.001')));
  });

  test('take-profit sits above the average, not above the last buy', () {
    final r = runDca([
      c(0, '100', '100', '85', '85'), // one safety order at 90
      c(1, '85', '120', '85', '120'), // the way back up
    ], params);

    final tp = r.trades.firstWhere((t) => t.side == TradeSide.sell);
    // Average of 100 and 90 by quote weight, plus 5 %.
    final held =
        (d('100') / d('100')).toDecimal(scaleOnInfinitePrecision: 8) +
        (d('100') / d('90')).toDecimal(scaleOnInfinitePrecision: 8);
    final average = (d('200') / held).toDecimal(scaleOnInfinitePrecision: 8);
    expect((tp.price - average * d('1.05')).abs(), lessThan(d('0.000001')));
    expect(tp.realizedPnl, greaterThan(Decimal.zero));
  });

  test('the multipliers widen the steps and grow the orders', () {
    final r = runDca(
      [c(0, '100', '100', '60', '60')],
      DcaParams(
        baseOrder: d('100'),
        safetyOrder: d('100'),
        safetyOrders: 2,
        stepPct: d('10'),
        takeProfitPct: d('5'),
        feeRate: Decimal.zero,
        stepMultiplier: d('2'),
        volumeMultiplier: d('2'),
      ),
    );

    // 100 → −10 % = 90 → −20 % = 72; orders 100, 100, 200.
    expect(r.trades.map((t) => '${t.price}'), ['100', '90', '72']);
    // Rounded quantities: within a cent of the order sizes.
    for (final (i, want) in ['100', '100', '200'].indexed) {
      expect((r.trades[i].value - d(want)).abs(), lessThan(d('0.01')));
    }
  });

  test('fees are paid on both legs and lower the realized figure', () {
    final fee = DcaParams(
      baseOrder: d('100'),
      safetyOrder: d('100'),
      safetyOrders: 0,
      stepPct: d('10'),
      takeProfitPct: d('5'),
      feeRate: d('0.001'),
    );
    final r = runDca([
      c(0, '100', '100', '100', '100'),
      c(1, '100', '110', '100', '110'),
    ], fee);
    final sell = r.trades.firstWhere((t) => t.side == TradeSide.sell);

    expect(r.fees, greaterThan(Decimal.zero));
    expect(sell.realizedPnl! < d('5'), isTrue);
    expect(sell.realizedPnl! > Decimal.zero, isTrue);
  });

  test('no candles, no trades', () {
    expect(runDca(const [], params).trades, isEmpty);
  });
}
