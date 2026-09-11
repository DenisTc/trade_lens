import 'package:chart/src/model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A moving average drawn over the candles.
///
/// Simple or exponential over closes; the line is only as long as the
/// data allows, so the first `period - 1` candles carry nothing rather
/// than a made-up value.
@immutable
final class MovingAverage {
  const MovingAverage({
    required this.period,
    required this.color,
    this.exponential = false,
    this.strokeWidth = 1.2,
  }) : assert(period > 0, 'a moving average needs a period');

  final int period;
  final Color color;
  final bool exponential;
  final double strokeWidth;

  /// What the legend calls it: `MA7`, `EMA25`.
  String get label => '${exponential ? 'EMA' : 'MA'}$period';

  /// One value per candle, null where fewer than [period] closes exist.
  ///
  /// Computed on the whole series rather than the visible range, because
  /// an average depends on candles that scrolled out of view.
  List<double?> compute(List<ChartCandle> candles) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < period) return out;
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += candles[i].close;
    }
    out[period - 1] = sum / period;
    if (exponential) {
      // Seeded with the first simple average, as charting tools do.
      final k = 2 / (period + 1);
      for (var i = period; i < candles.length; i++) {
        out[i] = candles[i].close * k + out[i - 1]! * (1 - k);
      }
    } else {
      for (var i = period; i < candles.length; i++) {
        sum += candles[i].close - candles[i - period].close;
        out[i] = sum / period;
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is MovingAverage &&
      other.period == period &&
      other.color == color &&
      other.exponential == exponential &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(period, color, exponential, strokeWidth);
}
