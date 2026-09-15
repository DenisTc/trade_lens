import 'package:backtest/src/result.dart';
import 'package:core/core.dart';
import 'package:meta/meta.dart';

/// Computed figures and the exact setup of one historical backtest.
/// Contains no raw candles or trades; safe to hand to a summary provider.
@immutable
final class BacktestMetrics {
  BacktestMetrics.fromResult(
    BacktestResult result, {
    required this.kind,
    required Map<String, String> params,
    required this.symbol,
    required this.intervalCode,
    required this.candleCount,
    required this.from,
    required this.to,
  }) : params = Map.unmodifiable(params),
       capital = result.capital,
       netProfit = result.netProfit,
       netProfitPct = result.netProfitPct,
       tradeCount = result.tradeCount,
       closedRoundTrips = result.closedRoundTrips,
       winningRoundTrips = result.winningRoundTrips,
       maxDrawdown = result.maxDrawdown,
       maxDrawdownPct = result.maxDrawdownPct,
       fees = result.fees,
       finalEquity = result.finalEquity,
       baseHeld = result.baseHeld;

  final String kind;
  final Map<String, String> params;
  final String symbol;
  final String intervalCode;
  final int candleCount;
  final DateTime from;
  final DateTime to;
  final Decimal capital;
  final Decimal netProfit;
  final Decimal? netProfitPct;
  final int tradeCount;
  final int closedRoundTrips;
  final int winningRoundTrips;
  final Decimal maxDrawdown;
  final Decimal? maxDrawdownPct;
  final Decimal fees;
  final Decimal finalEquity;
  final Decimal baseHeld;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'params': params,
    'symbol': symbol,
    'intervalCode': intervalCode,
    'candleCount': candleCount,
    'from': from.toUtc().toIso8601String(),
    'to': to.toUtc().toIso8601String(),
    'capital': capital.toString(),
    'netProfit': netProfit.toString(),
    'netProfitPct': netProfitPct?.toString(),
    'tradeCount': tradeCount,
    'closedRoundTrips': closedRoundTrips,
    'winningRoundTrips': winningRoundTrips,
    'maxDrawdown': maxDrawdown.toString(),
    'maxDrawdownPct': maxDrawdownPct?.toString(),
    'fees': fees.toString(),
    'finalEquity': finalEquity.toString(),
    'baseHeld': baseHeld.toString(),
  };
}
