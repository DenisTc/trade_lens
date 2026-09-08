/// Candle interval. [auto] is for sources that choose the granularity
/// themselves (CoinGecko OHLC); its [duration] is null and the actual
/// granularity travels with the candles.
enum Interval {
  m1(Duration(minutes: 1), '1m'),
  m15(Duration(minutes: 15), '15m'),
  h1(Duration(hours: 1), '1h'),
  d1(Duration(days: 1), '1d'),
  auto(null, 'auto');

  Interval(this.duration, this.code);

  final Duration? duration;

  /// Wire code, identical to Binance's interval string for fixed intervals.
  final String code;
}
