import 'package:flutter/foundation.dart';

/// A candle as the chart sees it. `double` on purpose: this package is the
/// presentation boundary and the only place where `Decimal` becomes a
/// floating-point number (in the caller's mapper, once).
@immutable
final class ChartCandle {
  const ChartCandle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;

  /// Null when the source has no volume (CoinGecko OHLC).
  final double? volume;

  bool get isUp => close >= open;

  @override
  bool operator ==(Object other) =>
      other is ChartCandle &&
      other.openTime == openTime &&
      other.open == open &&
      other.high == high &&
      other.low == low &&
      other.close == close &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(openTime, open, high, low, close, volume);

  @override
  String toString() => 'ChartCandle($openTime o$open h$high l$low c$close)';
}

/// Candle width in time, used for the time axis labels. `auto` sources
/// pass the granularity they actually returned.
@immutable
final class ChartInterval {
  const ChartInterval(this.duration, {this.label});

  final Duration duration;

  /// Human label, e.g. `1m`, `4h`, `30m (auto)`.
  final String? label;

  static const m1 = ChartInterval(Duration(minutes: 1), label: '1m');
  static const m15 = ChartInterval(Duration(minutes: 15), label: '15m');
  static const h1 = ChartInterval(Duration(hours: 1), label: '1h');
  static const d1 = ChartInterval(Duration(days: 1), label: '1d');

  @override
  bool operator ==(Object other) =>
      other is ChartInterval &&
      other.duration == duration &&
      other.label == label;

  @override
  int get hashCode => Object.hash(duration, label);
}
