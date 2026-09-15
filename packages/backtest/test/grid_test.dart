import 'package:backtest/backtest.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // Five levels 90…110, ten apart; the price opens at 100, so two sells
  // above and two buys below, one grid step apart.
  final params = GridParams(
    lower: d('90'),
    upper: d('110'),
    levels: 5,
    investment: d('1000'),
    feeRate: Decimal.zero,
  );

  for (final field in ['open', 'low', 'high', 'close']) {
    for (final value in ['0', '-1']) {
      test('skips $field = $value before and during a run, marking equity', () {
        final bad = c(
          0,
          field == 'open' ? value : '100',
          field == 'high' ? value : '110',
          field == 'low' ? value : '80',
          field == 'close' ? value : '100',
        );
        final first = c(1, '100', '100', '100', '100');
        final middle = bad.copyWith(
          openTime: c(2, '100', '100', '100', '100').openTime,
        );
        final last = c(3, '100', '106', '100', '106');
        final result = runGrid([bad, first, middle, last], params);

        expect(result.trades.first.at, first.openTime);
        expect(
          result.trades.where(
            (t) => t.at == bad.openTime || t.at == middle.openTime,
          ),
          isEmpty,
        );
        expect(result.trades.where((t) => t.at == last.openTime), isNotEmpty);
        expect(result.equity, hasLength(5));
        expect(result.equity[1].equity, params.investment);
        expect(result.equity.skip(1).map((p) => p.at), [
          bad.openTime,
          first.openTime,
          middle.openTime,
          last.openTime,
        ]);

        final onlyBad = runGrid([bad], params);
        expect(onlyBad.trades, isEmpty);
        expect(onlyBad.finalEquity, params.investment);
        expect(onlyBad.equity, hasLength(2));
      });
    }
  }

  test('levels are evenly spaced, ascending', () {
    expect(params.prices.map((p) => '$p'), ['90', '95', '100', '105', '110']);
  });

  test('the start-up buy covers the sells above the entry, nothing more', () {
    final r = runGrid([c(0, '100', '100', '100', '100')], params);

    expect(r.trades, hasLength(1));
    expect(r.trades.single.side, TradeSide.buy);
    // Two units at 100 plus one buy each at 95 and 90 = 385 per unit.
    final qty = (d('1000') / d('385')).toDecimal(scaleOnInfinitePrecision: 8);
    expect(r.trades.single.qty, qty * Decimal.fromInt(2));
    expect(
      r.finalEquity,
      d('1000'),
      reason: 'marked at the entry, nothing moved',
    );
  });

  test('a swing down and back up earns one step per round trip', () {
    final candles = [
      c(0, '100', '100', '89', '89'), // buys at 95 and 90
      c(1, '89', '111', '89', '111'), // sells at 95, 100, 105, 110
    ];
    final r = runGrid(candles, params);

    final sides = r.trades.map((t) => t.side.name).toList();
    expect(sides, ['buy', 'buy', 'buy', 'sell', 'sell', 'sell', 'sell']);
    expect(
      r.trades.where((t) => t.side == TradeSide.sell).map((t) => '${t.price}'),
      ['95', '100', '105', '110'],
    );
    // A sell placed by a buy earns one grid step; a sell backed by the
    // start-up purchase at the entry earns its distance from the entry.
    final qty = (d('1000') / d('385')).toDecimal(scaleOnInfinitePrecision: 8);
    expect(
      r.trades.where((t) => t.side == TradeSide.sell).map((t) => t.realizedPnl),
      [qty * d('5'), qty * d('5'), qty * d('5'), qty * d('10')],
    );
    expect(r.closedRoundTrips, 4);
    expect(r.winningRoundTrips, 4);
    expect(r.baseHeld, Decimal.zero, reason: 'everything above sold');
    expect(r.netProfit, qty * d('25'));
    expect(r.netProfitPct, greaterThan(Decimal.zero));
  });

  test('fees come off both legs of a round trip', () {
    final fee = params.copyWithFee(d('0.001'));
    final r = runGrid([
      c(0, '100', '100', '94', '94'),
      c(1, '94', '101', '94', '101'),
    ], fee);
    final sell = r.trades.lastWhere((t) => t.side == TradeSide.sell);

    expect(sell.fee, sell.value * d('0.001'));
    expect(sell.realizedPnl! < sell.qty * d('5'), isTrue);
    expect(r.fees, greaterThan(Decimal.zero));
  });

  test('a fall through the whole grid is a drawdown, not a crash', () {
    final r = runGrid([c(0, '100', '100', '80', '80')], params);

    expect(r.buysBelow, 2);
    expect(r.finalEquity, lessThan(d('1000')));
    expect(r.maxDrawdown, d('1000') - r.finalEquity);
    expect(r.quoteHeld, greaterThanOrEqualTo(Decimal.zero));
  });

  test('no candles, no trades', () {
    expect(runGrid(const [], params).trades, isEmpty);
  });
}

extension on GridParams {
  GridParams copyWithFee(Decimal fee) => GridParams(
    lower: lower,
    upper: upper,
    levels: levels,
    investment: investment,
    feeRate: fee,
  );
}

extension on BacktestResult {
  int get buysBelow => trades.where((t) => t.side == TradeSide.buy).length - 1;
}
