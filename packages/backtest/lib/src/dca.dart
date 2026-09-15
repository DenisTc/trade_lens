import 'package:backtest/src/money.dart';
import 'package:backtest/src/path.dart';
import 'package:backtest/src/result.dart';
import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';

/// A DCA bot, long only: a base order at the start, then safety orders
/// at every further fall of [stepPct] — each step [stepMultiplier] times
/// the previous, each order [volumeMultiplier] times the previous — and
/// one take-profit sell of the whole position that nets [takeProfitPct]
/// over what the round cost, fees on both legs included. After the
/// take-profit the next round starts where the price is.
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

  /// Quote spent on the first buy of a round, fee included.
  final Decimal baseOrder;

  /// Quote spent on the first safety order, fee included.
  final Decimal safetyOrder;
  final int safetyOrders;

  /// Fall from the last fill, in percent, that triggers the next safety
  /// order.
  final Decimal stepPct;

  /// Net gain of a round over its cost, in percent, that closes it.
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

/// Runs the bot over [candles], oldest first.
///
/// A round that lost money leaves less quote than the next one wants:
/// orders then shrink to what is there, and a round with nothing to
/// spend does not open. Nothing is ever bought on credit.
BacktestResult runDca(List<Candle> candles, DcaParams params) {
  final ledger = Ledger(feeRate: params.feeRate, quote: params.capital);
  if (candles.isEmpty) return ledger.result(Decimal.zero);
  final hundred = Decimal.fromInt(100);
  final stepFraction = Money.price(params.stepPct / hundred);
  final gain = Decimal.one + Money.price(params.takeProfitPct / hundred);
  final afterFee = Decimal.one - params.feeRate;

  // The round in progress.
  var cost = Decimal.zero; // quote spent, fees included
  var held = Decimal.zero; // base bought
  var safetyLeft = 0;
  var nextOrder = Decimal.zero;
  var nextStep = Decimal.zero;
  Decimal? nextBuy; // safety order price
  Decimal? takeProfit;

  /// Spends [quote] at [price]; less when less is there. False when
  /// nothing could be bought.
  bool fill(DateTime at, Decimal price, Decimal quote) {
    final outlay = quote < ledger.quoteHeld ? quote : ledger.quoteHeld;
    if (outlay <= Decimal.zero ||
        price <= Decimal.zero ||
        afterFee <= Decimal.zero ||
        Decimal.one + params.feeRate <= Decimal.zero) {
      return false;
    }
    // Fees come out of the outlay, so it is the whole of what is spent.
    final qty = Money.qty(outlay / (price * (Decimal.one + params.feeRate)));
    if (qty <= Decimal.zero) return false;
    ledger.buy(at, price, qty);
    cost += price * qty * (Decimal.one + params.feeRate); // exact, as paid
    held += qty;
    // The sell that returns cost × gain after its own fee.
    takeProfit = Money.priceUp(cost * gain / (held * afterFee));
    if (safetyLeft > 0) {
      nextBuy = Money.roundPrice(price * (Decimal.one - nextStep));
      nextStep = Money.roundPrice(
        nextStep * (params.stepMultiplier ?? Decimal.one),
      );
    } else {
      nextBuy = null;
    }
    return true;
  }

  void open(DateTime at, Decimal price) {
    cost = Decimal.zero;
    held = Decimal.zero;
    safetyLeft = params.safetyOrders;
    nextOrder = params.safetyOrder;
    nextStep = stepFraction;
    takeProfit = null;
    nextBuy = null;
    fill(at, price, params.baseOrder);
  }

  void walk(DateTime time, Decimal from, Decimal to) {
    if (to <= from) {
      // Falling: safety orders, one after another, as long as the leg
      // reaches them and the quote pays for them.
      while (true) {
        final price = nextBuy;
        if (price == null || price < to || price > from) break;
        final order = nextOrder;
        safetyLeft--;
        nextOrder = order * (params.volumeMultiplier ?? Decimal.one);
        if (!fill(time, price, order)) {
          nextBuy = null;
          break;
        }
      }
    }
    if (to >= from) {
      // Rising: a take-profit closes the round and the next one opens
      // right there, whose own take-profit may still be on this leg.
      while (true) {
        final tp = takeProfit;
        if (tp == null || tp < from || tp > to) break;
        ledger.sell(time, tp, held, cost: cost);
        open(time, tp);
        // Nothing left to open with, or a take-profit that rounded back
        // onto the price it opened at: the leg is done either way.
        final next = takeProfit;
        if (next == null || next <= tp) break;
      }
    }
  }

  var started = false;
  for (final candle in candles) {
    if (!isUsableCandle(candle)) {
      ledger.mark(candle.openTime, candle.close);
      continue;
    }
    if (!started) {
      open(candle.openTime, candle.open);
      started = true;
    }
    final path = candlePath(candle);
    var from = path.first;
    walk(candle.openTime, from, from);
    for (final to in path.skip(1)) {
      walk(candle.openTime, from, to);
      from = to;
    }
    ledger.mark(candle.openTime, candle.close);
  }
  return ledger.result(candles.last.close);
}
