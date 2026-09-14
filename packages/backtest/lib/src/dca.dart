import 'package:backtest/src/path.dart';
import 'package:backtest/src/result.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';

/// A DCA bot, long only: a base order at the start, then safety orders
/// at every further fall of [stepPct] — each step [stepMultiplier] times
/// the previous, each order [volumeMultiplier] times the previous — and
/// one take-profit sell of the whole position [takeProfitPct] above the
/// average entry, fees on both legs included. After the take-profit the
/// next round starts where the price is.
@immutable
final class DcaParams {
  const DcaParams({
    required this.baseOrder,
    required this.safetyOrder,
    required this.safetyOrders,
    required this.stepPct,
    required this.takeProfitPct,
    required this.feeRate,
    this.stepMultiplier,
    this.volumeMultiplier,
  });

  /// Quote spent on the first buy of a round.
  final Decimal baseOrder;

  /// Quote spent on the first safety order.
  final Decimal safetyOrder;
  final int safetyOrders;

  /// Fall from the last fill, in percent, that triggers the next safety
  /// order.
  final Decimal stepPct;
  final Decimal takeProfitPct;
  final Decimal feeRate;

  /// Each next step is this many times the previous; 1 when null.
  final Decimal? stepMultiplier;
  final Decimal? volumeMultiplier;

  /// Everything one round can spend: the capital the run needs.
  Decimal get capital {
    var total = baseOrder;
    var order = safetyOrder;
    for (var i = 0; i < safetyOrders; i++) {
      total += order;
      order *= volumeMultiplier ?? Decimal.one;
    }
    return total;
  }
}

BacktestResult runDca(List<Candle> candles, DcaParams params) {
  final ledger = Ledger(feeRate: params.feeRate, quote: params.capital);
  if (candles.isEmpty) return ledger.result(Decimal.zero);
  final hundred = Decimal.fromInt(100);

  // The round in progress.
  var cost = Decimal.zero; // quote spent, fees included
  var held = Decimal.zero; // base bought
  var safetyLeft = 0;
  var nextOrder = Decimal.zero;
  var nextStepPct = Decimal.zero;
  Decimal? nextBuy; // safety order price
  Decimal? takeProfit;

  Decimal scaled(Decimal value, Decimal fraction) =>
      value * (Decimal.one - fraction);

  void fill(DateTime at, Decimal price, Decimal quote) {
    // Fees come out of the quote spent, so `quote` is the whole outlay.
    final qty = (quote / (price * (Decimal.one + params.feeRate))).toDecimal(
      scaleOnInfinitePrecision: 8,
    );
    ledger.buy(at, price, qty);
    cost += price * qty * (Decimal.one + params.feeRate);
    held += qty;
    final average = (cost / held).toDecimal(scaleOnInfinitePrecision: 8);
    final lift = (params.takeProfitPct / hundred).toDecimal(
      scaleOnInfinitePrecision: 8,
    );
    takeProfit = average * (Decimal.one + lift);
    if (safetyLeft > 0) {
      nextBuy = scaled(
        price,
        (nextStepPct / hundred).toDecimal(scaleOnInfinitePrecision: 8),
      );
      nextStepPct *= params.stepMultiplier ?? Decimal.one;
    } else {
      nextBuy = null;
    }
  }

  void open(DateTime at, Decimal price) {
    cost = Decimal.zero;
    held = Decimal.zero;
    safetyLeft = params.safetyOrders;
    nextOrder = params.safetyOrder;
    nextStepPct = params.stepPct;
    fill(at, price, params.baseOrder);
  }

  open(candles.first.openTime, candles.first.open);

  for (final candle in candles) {
    final path = candlePath(candle);
    var from = path.first;
    for (final to in path.skip(1)) {
      if (to < from) {
        // Falling: safety orders, one after another, as long as the leg
        // reaches them.
        while (true) {
          final price = nextBuy;
          if (price == null || price < to || price > from) break;
          final order = nextOrder;
          safetyLeft--;
          nextOrder = order * (params.volumeMultiplier ?? Decimal.one);
          fill(candle.openTime, price, order);
          from = price;
        }
      } else if (to > from) {
        final tp = takeProfit;
        if (tp != null && tp >= from && tp <= to) {
          ledger.sell(candle.openTime, tp, held, cost: cost);
          // The next round starts here, at the take-profit price: the
          // rest of this leg is rising, so it cannot buy more on it.
          open(candle.openTime, tp);
          from = tp;
        }
      }
      from = to;
    }
    ledger.mark(candle.openTime, candle.close);
  }
  return ledger.result(candles.last.close);
}
