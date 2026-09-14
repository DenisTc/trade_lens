import 'package:core/core.dart';
import 'package:meta/meta.dart';

enum TradeSide { buy, sell }

/// One fill. [realizedPnl] is set on the sell that closes a round trip:
/// proceeds minus the cost of what was sold, fees on both legs included.
@immutable
final class BacktestTrade {
  const BacktestTrade({
    required this.at,
    required this.side,
    required this.price,
    required this.qty,
    required this.fee,
    this.realizedPnl,
  });

  final DateTime at;
  final TradeSide side;
  final Decimal price;
  final Decimal qty;

  /// In quote currency.
  final Decimal fee;
  final Decimal? realizedPnl;

  Decimal get value => price * qty;
}

/// Equity at the close of one candle: quote held plus base held at the
/// close. The curve the drawdown is read from.
@immutable
final class EquityPoint {
  const EquityPoint({required this.at, required this.equity});

  final DateTime at;
  final Decimal equity;
}

/// What a run says about itself. Every money figure is in the quote
/// currency; percentages are of the capital the strategy started with.
@immutable
final class BacktestResult {
  const BacktestResult({
    required this.capital,
    required this.trades,
    required this.equity,
    required this.finalEquity,
    required this.fees,
    required this.maxDrawdown,
    required this.baseHeld,
    required this.quoteHeld,
  });

  /// Quote the strategy was given at the start.
  final Decimal capital;
  final List<BacktestTrade> trades;
  final List<EquityPoint> equity;

  /// Quote plus base marked at the last close. Open positions are part of
  /// it: a bot that bought and never sold is not "flat", it is long.
  final Decimal finalEquity;
  final Decimal fees;

  /// Largest peak-to-trough fall of the equity curve, in quote.
  final Decimal maxDrawdown;
  final Decimal baseHeld;
  final Decimal quoteHeld;

  Decimal get netProfit => finalEquity - capital;

  /// Percent of [capital]; null when nothing was invested.
  Decimal? get netProfitPct => _pct(netProfit, capital);
  Decimal? get maxDrawdownPct => _pct(maxDrawdown, capital);

  int get tradeCount => trades.length;

  /// Sells that closed a round trip and made money, against all that did.
  int get winningRoundTrips => trades
      .where((t) => (t.realizedPnl ?? Decimal.zero) > Decimal.zero)
      .length;
  int get closedRoundTrips => trades.where((t) => t.realizedPnl != null).length;

  static Decimal? _pct(Decimal part, Decimal whole) => whole == Decimal.zero
      ? null
      : (part * Decimal.fromInt(100) / whole).toDecimal(
          scaleOnInfinitePrecision: 4,
        );
}

/// Peak-to-trough on a curve; zero for a curve that only rises.
Decimal maxDrawdownOf(Iterable<Decimal> curve) {
  var peak = Decimal.zero;
  var worst = Decimal.zero;
  var first = true;
  for (final v in curve) {
    if (first || v > peak) {
      peak = v;
      first = false;
    }
    final fall = peak - v;
    if (fall > worst) worst = fall;
  }
  return worst;
}

/// Shared bookkeeping of a run: what is held, what was paid, what it is
/// worth at each close.
final class Ledger {
  Ledger({required this.feeRate, required Decimal quote})
    : quoteHeld = quote,
      capital = quote;

  /// Fee taken on the quote value of every fill, e.g. `0.001` for 0.1 %.
  final Decimal feeRate;
  final Decimal capital;
  Decimal quoteHeld;
  Decimal baseHeld = Decimal.zero;
  Decimal fees = Decimal.zero;
  final trades = <BacktestTrade>[];
  final equity = <EquityPoint>[];

  Decimal feeOn(Decimal value) => value * feeRate;

  void buy(DateTime at, Decimal price, Decimal qty) {
    final value = price * qty;
    final fee = feeOn(value);
    quoteHeld -= value + fee;
    baseHeld += qty;
    fees += fee;
    trades.add(
      BacktestTrade(
        at: at,
        side: TradeSide.buy,
        price: price,
        qty: qty,
        fee: fee,
      ),
    );
  }

  /// [cost] is what the sold base cost to acquire, fees on the buys
  /// included, so the realized figure is honest about both legs.
  void sell(DateTime at, Decimal price, Decimal qty, {required Decimal cost}) {
    final value = price * qty;
    final fee = feeOn(value);
    quoteHeld += value - fee;
    baseHeld -= qty;
    fees += fee;
    trades.add(
      BacktestTrade(
        at: at,
        side: TradeSide.sell,
        price: price,
        qty: qty,
        fee: fee,
        realizedPnl: value - fee - cost,
      ),
    );
  }

  void mark(DateTime at, Decimal close) =>
      equity.add(EquityPoint(at: at, equity: quoteHeld + baseHeld * close));

  BacktestResult result(Decimal lastClose) => BacktestResult(
    capital: capital,
    trades: List.unmodifiable(trades),
    // The curve starts at the capital, the point the drawdown is read
    // from too.
    equity: List.unmodifiable([
      if (equity.isNotEmpty) EquityPoint(at: equity.first.at, equity: capital),
      ...equity,
    ]),
    finalEquity: quoteHeld + baseHeld * lastClose,
    fees: fees,
    maxDrawdown: maxDrawdownOf([capital, ...equity.map((p) => p.equity)]),
    baseHeld: baseHeld,
    quoteHeld: quoteHeld,
  );
}
