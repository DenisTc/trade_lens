import 'dart:math' as math;

import 'package:chart/src/model.dart';
import 'package:flutter/foundation.dart';

/// Which candles are on screen: the index of the first visible candle and
/// the width of one candle in pixels. Zoom changes the width, pan changes
/// the index. Value type, so painters can compare instances.
@immutable
final class ChartViewport {
  const ChartViewport({
    required this.firstIndex,
    required this.candleWidth,
    this.minCandleWidth = 2,
    this.maxCandleWidth = 40,
    this.rightPaddingCandles = 2,
  });

  /// Index of the first candle drawn at the left edge (may be fractional
  /// while panning for sub-candle smoothness).
  final double firstIndex;
  final double candleWidth;
  final double minCandleWidth;
  final double maxCandleWidth;

  /// Empty space kept after the last candle so the live one is not glued
  /// to the price axis.
  final int rightPaddingCandles;

  int visibleCount(double plotWidth) => (plotWidth / candleWidth).ceil();

  /// Index just past the last visible candle.
  double lastIndex(double plotWidth) => firstIndex + plotWidth / candleWidth;

  /// True when the newest candle is on screen: the viewport follows new
  /// candles. Once the user pans back into history it stops following.
  bool isAtEnd(int total, double plotWidth) =>
      lastIndex(plotWidth) >= total + rightPaddingCandles - 0.5;

  /// The viewport that shows the newest candles for [total].
  ChartViewport stickToEnd(int total, double plotWidth) => copyWith(
    firstIndex: math.max(
      0,
      total + rightPaddingCandles - plotWidth / candleWidth,
    ),
  );

  /// Zoom by [factor] (>1 zooms in) keeping the candle under [focalX]
  /// (pixels from the plot's left edge) in place.
  ChartViewport zoomAt(
    double factor,
    double focalX,
    int total,
    double plotWidth,
  ) {
    final width = (candleWidth * factor).clamp(minCandleWidth, maxCandleWidth);
    if (width == candleWidth) return this;
    final focalIndex = firstIndex + focalX / candleWidth;
    final next = copyWith(
      candleWidth: width,
      firstIndex: focalIndex - focalX / width,
    );
    return next.clamped(total, plotWidth);
  }

  /// Pan by [dx] pixels (positive drags the chart to the right, i.e. shows
  /// older candles).
  ChartViewport pan(double dx, int total, double plotWidth) =>
      copyWith(firstIndex: firstIndex - dx / candleWidth)
          .clamped(total, plotWidth);

  /// Keeps at least one candle on screen and never scrolls past the
  /// right padding.
  ChartViewport clamped(int total, double plotWidth) {
    if (total == 0) return copyWith(firstIndex: 0);
    final visible = plotWidth / candleWidth;
    final maxFirst = math.max(0, total + rightPaddingCandles - visible);
    return copyWith(firstIndex: firstIndex.clamp(0, maxFirst.toDouble()));
  }

  /// Pixel x of the *centre* of candle [index] inside the plot.
  double xOf(int index) => (index - firstIndex + 0.5) * candleWidth;

  /// Candle index under pixel [x] inside a plot of [plotWidth], or null
  /// outside the plot or the series (the price axis is not the plot).
  int? indexAt(double x, int total, {double? plotWidth}) {
    if (x < 0 || (plotWidth != null && x >= plotWidth)) return null;
    final index = (firstIndex + x / candleWidth).floor();
    return index >= 0 && index < total ? index : null;
  }

  /// Visible index range `[start, end)`: candles that intersect the plot,
  /// clamped to the series. A candle fully past the right edge is not
  /// visible and must not stretch the price range.
  (int, int) visibleRange(int total, double plotWidth) {
    final start = math.max(0, firstIndex.floor());
    final end = math.min(total, lastIndex(plotWidth).ceil());
    return (start, math.max(start, end));
  }

  /// One gesture step: scale by [factor] around [focalX] *and* pan by
  /// [dx], clamped once at the end so an intermediate clamp cannot move the
  /// candle from under the fingers.
  ChartViewport transformed({
    required double factor,
    required double focalX,
    required double dx,
    required int total,
    required double plotWidth,
  }) {
    final width = (candleWidth * factor).clamp(minCandleWidth, maxCandleWidth);
    final focalIndex = firstIndex + focalX / candleWidth;
    return copyWith(
      candleWidth: width,
      firstIndex: focalIndex - (focalX + dx) / width,
    ).clamped(total, plotWidth);
  }

  /// Price extent of the visible candles with a little headroom, or null
  /// when nothing is visible.
  ({double min, double max})? priceRange(
    List<ChartCandle> candles,
    double plotWidth,
  ) {
    final (start, end) = visibleRange(candles.length, plotWidth);
    if (start >= end) return null;
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (var i = start; i < end; i++) {
      min = math.min(min, candles[i].low);
      max = math.max(max, candles[i].high);
    }
    if (min == max) {
      final pad = min == 0 ? 1 : min.abs() * 0.01;
      return (min: min - pad, max: max + pad);
    }
    final pad = (max - min) * 0.05;
    return (min: min - pad, max: max + pad);
  }

  /// Largest visible volume, for scaling the volume bars.
  double maxVolume(List<ChartCandle> candles, double plotWidth) {
    final (start, end) = visibleRange(candles.length, plotWidth);
    var max = 0.0;
    for (var i = start; i < end; i++) {
      max = math.max(max, candles[i].volume ?? 0);
    }
    return max;
  }

  ChartViewport copyWith({double? firstIndex, double? candleWidth}) =>
      ChartViewport(
        firstIndex: firstIndex ?? this.firstIndex,
        candleWidth: candleWidth ?? this.candleWidth,
        minCandleWidth: minCandleWidth,
        maxCandleWidth: maxCandleWidth,
        rightPaddingCandles: rightPaddingCandles,
      );

  @override
  bool operator ==(Object other) =>
      other is ChartViewport &&
      other.firstIndex == firstIndex &&
      other.candleWidth == candleWidth &&
      other.minCandleWidth == minCandleWidth &&
      other.maxCandleWidth == maxCandleWidth &&
      other.rightPaddingCandles == rightPaddingCandles;

  @override
  int get hashCode => Object.hash(
    firstIndex,
    candleWidth,
    minCandleWidth,
    maxCandleWidth,
    rightPaddingCandles,
  );

  @override
  String toString() => 'ChartViewport(first: $firstIndex, w: $candleWidth)';
}
