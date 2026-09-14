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

  /// Level prices, ascending.
  List<Decimal> get prices {
    final step = ((upper - lower) / Decimal.fromInt(levels - 1)).toDecimal(
      scaleOnInfinitePrecision: 8,
    );
    return [for (var i = 0; i < levels; i++) lower + step * Decimal.fromInt(i)];
  }
}

/// Runs a grid over [candles], oldest first. Empty candles or a range
/// the first open is outside of yield a run with no trades.
BacktestResult runGrid(List<Candle> candles, GridParams params) {
  final ledger = Ledger(feeRate: params.feeRate, quote: params.investment);
  if (candles.isEmpty) return ledger.result(Decimal.zero);
  final prices = params.prices;
  final entry = candles.first.open;

  // Levels above the entry sell inventory bought now at the entry; levels
  // below wait with a buy; a level exactly at the entry holds nothing
  // until a neighbour fills. Same quantity everywhere.
  final above = prices.where((p) => p > entry).toList();
  final below = prices.where((p) => p < entry).toList();
  final costPerUnit =
      entry * Decimal.fromInt(above.length) +
      below.fold(Decimal.zero, (sum, p) => sum + p);
  final grossPerUnit =
      costPerUnit * (Decimal.one + params.feeRate); // fees on the buys too
  if (grossPerUnit == Decimal.zero) return ledger.result(candles.last.close);
  final qty = (params.investment / grossPerUnit).toDecimal(
    scaleOnInfinitePrecision: 8,
  );

  // Orders by level index: a sell backed by base bought at `cost`, or a
  // buy. `null` is a level with nothing resting on it (the entry level).
  final sells = <int, Decimal>{}; // level → cost basis of the base it sells
  final buys = <int>{};
  final at = candles.first.openTime;
  if (above.isNotEmpty) {
    ledger.buy(at, entry, qty * Decimal.fromInt(above.length));
    final unitCost = entry * qty * (Decimal.one + params.feeRate);
    for (var i = 0; i < prices.length; i++) {
      if (prices[i] > entry) sells[i] = unitCost;
    }
  }
  for (var i = 0; i < prices.length; i++) {
    if (prices[i] < entry) buys.add(i);
  }

  for (final candle in candles) {
    final path = candlePath(candle);
    var from = path.first;
    for (final to in path.skip(1)) {
      if (to < from) {
        // Falling: buys fill from the highest down, each placing a sell
        // one level up, which cannot fill on this leg.
        while (true) {
          final hit = buys.where((i) => prices[i] <= from && prices[i] >= to);
          if (hit.isEmpty) break;
          final i = hit.reduce((a, b) => prices[a] > prices[b] ? a : b);
          buys.remove(i);
          ledger.buy(candle.openTime, prices[i], qty);
          if (i + 1 < prices.length) {
            sells[i + 1] = prices[i] * qty * (Decimal.one + params.feeRate);
          }
          from = prices[i];
        }
      } else if (to > from) {
        while (true) {
          final hit = sells.keys.where(
            (i) => prices[i] >= from && prices[i] <= to,
          );
          if (hit.isEmpty) break;
          final i = hit.reduce((a, b) => prices[a] < prices[b] ? a : b);
          final cost = sells.remove(i)!;
          ledger.sell(candle.openTime, prices[i], qty, cost: cost);
          if (i - 1 >= 0) buys.add(i - 1);
          from = prices[i];
        }
      }
      from = to;
    }
    ledger.mark(candle.openTime, candle.close);
  }
  return ledger.result(candles.last.close);
}
