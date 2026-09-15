import 'dart:collection';

import 'package:backtest/src/money.dart';
import 'package:backtest/src/path.dart';
import 'package:backtest/src/result.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';

/// A spot grid: [levels] prices evenly spaced from [lower] to [upper].
/// Below the starting price every level holds a buy order, above it a
/// sell order backed by base bought at the start. A filled buy places a
/// sell one level up; a filled sell places a buy one level down. Each
/// round trip earns one grid step, minus fees on both legs.
///
/// [investment] is split so that every level trades the same base
/// quantity: the start-up purchase for the levels above the entry price
/// plus one buy at every level below it must not exceed it.
@immutable
final class GridParams {
  const GridParams({
    required this.lower,
    required this.upper,
    required this.levels,
    required this.investment,
    required this.feeRate,
  }) : assert(levels >= 2, 'a grid needs at least two levels');

  final Decimal lower;
  final Decimal upper;
  final int levels;
  final Decimal investment;

  /// Fraction of each fill's value, e.g. `0.001` for 0.1 %.
  final Decimal feeRate;

  /// Level prices, ascending; the ends are exactly [lower] and [upper].
  List<Decimal> get prices {
    final span = upper - lower;
    final n = Decimal.fromInt(levels - 1);
    return [
      for (var i = 0; i < levels - 1; i++)
        lower + Money.price(span * Decimal.fromInt(i) / n),
      upper,
    ];
  }
}

/// Runs a grid over [candles], oldest first. No usable candles, or a first
/// usable open outside the range, yield a run with no trades: a grid is not
/// started against a price it does not cover.
BacktestResult runGrid(List<Candle> candles, GridParams params) {
  final ledger = Ledger(feeRate: params.feeRate, quote: params.investment);
  if (candles.isEmpty) return ledger.result(Decimal.zero);
  final firstUsable = candles.indexWhere(isUsableCandle);
  if (firstUsable == -1) {
    for (final candle in candles) {
      ledger.mark(candle.openTime, candle.close);
    }
    return ledger.result(candles.last.close);
  }
  final prices = params.prices;
  final entry = candles[firstUsable].open;
  if (entry < params.lower || entry > params.upper) {
    for (final candle in candles) {
      ledger.mark(candle.openTime, candle.close);
    }
    return ledger.result(candles.last.close);
  }

  // Levels above the entry sell inventory bought now at the entry; levels
  // below wait with a buy; a level exactly at the entry holds nothing
  // until a neighbour fills. Same quantity everywhere.
  final above = prices.where((p) => p > entry).toList();
  final below = prices.where((p) => p < entry).toList();
  final costPerUnit =
      entry * Decimal.fromInt(above.length) +
      below.fold(Decimal.zero, (sum, p) => sum + p);
  final grossPerUnit = costPerUnit * (Decimal.one + params.feeRate);
  if (grossPerUnit <= Decimal.zero) {
    for (final candle in candles) {
      ledger.mark(candle.openTime, candle.close);
    }
    return ledger.result(candles.last.close);
  }
  final qty = Money.qty(params.investment / grossPerUnit);
  // Too little for one unit per level at this precision: no grid.
  if (qty <= Decimal.zero) {
    for (final candle in candles) {
      ledger.mark(candle.openTime, candle.close);
    }
    return ledger.result(candles.last.close);
  }

  // What rests on each level. A level can hold several lots: a sell
  // placed by a buy below lands on a level that may already hold one,
  // and both must sell. Sells remember what their base cost.
  final sells = <int, Queue<Decimal>>{};
  final buys = <int, int>{};
  for (final candle in candles.take(firstUsable)) {
    ledger.mark(candle.openTime, candle.close);
  }
  final at = candles[firstUsable].openTime;
  if (above.isNotEmpty) {
    ledger.buy(at, entry, qty * Decimal.fromInt(above.length));
    final unitCost = entry * qty * (Decimal.one + params.feeRate);
    for (var i = 0; i < prices.length; i++) {
      if (prices[i] > entry) sells[i] = Queue.of([unitCost]);
    }
  }
  for (var i = 0; i < prices.length; i++) {
    if (prices[i] < entry) buys[i] = 1;
  }

  // A buy the quote cannot pay for stays resting: the bot would not
  // have been able to place it either.
  bool fillBuy(DateTime time, int i) {
    final value = prices[i] * qty;
    if (ledger.quoteHeld < value + ledger.feeOn(value)) return false;
    buys[i] = buys[i]! - 1;
    if (buys[i] == 0) buys.remove(i);
    ledger.buy(time, prices[i], qty);
    if (i + 1 < prices.length) {
      sells
          .putIfAbsent(i + 1, Queue.new)
          .add(prices[i] * qty * (Decimal.one + params.feeRate));
    }
    return true;
  }

  void fillSell(DateTime time, int i) {
    final lots = sells[i]!;
    final cost = lots.removeFirst();
    if (lots.isEmpty) sells.remove(i);
    ledger.sell(time, prices[i], qty, cost: cost);
    if (i - 1 >= 0) buys[i - 1] = (buys[i - 1] ?? 0) + 1;
  }

  /// Fills everything resting between [from] and [to] on a leg walked
  /// in that direction: buys highest first when falling, sells lowest
  /// first when rising. An order at [from] itself counts — that is how
  /// an order at the open, or on a flat leg, fills.
  void walk(DateTime time, Decimal from, Decimal to) {
    if (to <= from) {
      final skipped = <int>{};
      while (true) {
        final hit = buys.keys.where(
          (i) => prices[i] <= from && prices[i] >= to && !skipped.contains(i),
        );
        if (hit.isEmpty) break;
        final i = hit.reduce((a, b) => prices[a] > prices[b] ? a : b);
        if (!fillBuy(time, i)) skipped.add(i);
      }
    }
    if (to >= from) {
      while (true) {
        final hit = sells.keys.where(
          (i) => prices[i] >= from && prices[i] <= to,
        );
        if (hit.isEmpty) break;
        fillSell(time, hit.reduce((a, b) => prices[a] < prices[b] ? a : b));
      }
    }
  }

  for (final candle in candles.skip(firstUsable)) {
    if (!isUsableCandle(candle)) {
      ledger.mark(candle.openTime, candle.close);
      continue;
    }
    final path = candlePath(candle);
    var from = path.first;
    // The open itself: whatever rests exactly there fills before the
    // candle moves anywhere.
    walk(candle.openTime, from, from);
    for (final to in path.skip(1)) {
      walk(candle.openTime, from, to);
      from = to;
    }
    ledger.mark(candle.openTime, candle.close);
  }
  return ledger.result(candles.last.close);
}
