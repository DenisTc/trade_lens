import 'dart:math' as math;

import 'package:chart/src/axes.dart';
import 'package:chart/src/chart_theme.dart';
import 'package:chart/src/model.dart';
import 'package:chart/src/series.dart';
import 'package:chart/src/viewport.dart';
import 'package:flutter/rendering.dart';

/// Geometry shared by the candle and crosshair painters so both map
/// prices and indices to the same pixels.
final class PlotGeometry {
  PlotGeometry({
    required this.size,
    required this.theme,
    required this.viewport,
    required this.candles,
    required this.showVolume,
  }) : plotWidth = math.max(0, size.width - theme.priceAxisWidth),
       plotHeight = math.max(0, size.height - theme.timeAxisHeight) {
    volumeHeight = showVolume ? plotHeight * theme.volumeFraction : 0;
    priceHeight = plotHeight - volumeHeight;
    range = viewport.priceRange(candles, plotWidth);
    maxVolume = showVolume ? viewport.maxVolume(candles, plotWidth) : 0;
  }

  final Size size;
  final CandleChartTheme theme;
  final ChartViewport viewport;
  final List<ChartCandle> candles;
  final bool showVolume;
  final double plotWidth;
  final double plotHeight;
  late final double volumeHeight;
  late final double priceHeight;
  late final ({double min, double max})? range;
  late final double maxVolume;

  Rect get plotRect => Rect.fromLTWH(0, 0, plotWidth, plotHeight);

  double yOf(double price) {
    final r = range;
    if (r == null) return priceHeight / 2;
    return priceHeight * (1 - (price - r.min) / (r.max - r.min));
  }

  double priceAt(double y) {
    final r = range;
    if (r == null) return 0;
    return r.max - (y / priceHeight) * (r.max - r.min);
  }

  double xOf(int index) => viewport.xOf(index);

  int? indexAt(double x) =>
      viewport.indexAt(x, candles.length, plotWidth: plotWidth);
}

/// Candles, volume bars, grid and both axes. Repaints only when the series
/// instance, the viewport or the theme changes.
final class CandlePainter extends CustomPainter {
  CandlePainter({
    required this.series,
    required this.viewport,
    required this.theme,
    required this.interval,
    required this.labels,
    this.showVolume = true,
    this.localTime = true,
  });

  final CandleSeries series;
  final ChartViewport viewport;
  final CandleChartTheme theme;
  final ChartInterval interval;
  final LabelCache labels;
  final bool showVolume;
  final bool localTime;

  @override
  void paint(Canvas canvas, Size size) {
    final candles = series.candles;
    final geometry = PlotGeometry(
      size: size,
      theme: theme,
      viewport: viewport,
      candles: candles,
      showVolume: showVolume,
    );
    _paintPriceAxis(canvas, geometry);
    if (geometry.range == null) return;
    canvas
      ..save()
      ..clipRect(geometry.plotRect);
    _paintCandles(canvas, geometry);
    canvas.restore();
    _paintTimeAxis(canvas, geometry);
  }

  void _paintCandles(Canvas canvas, PlotGeometry g) {
    final (start, end) = viewport.visibleRange(g.candles.length, g.plotWidth);
    final bodyWidth = math.max(1, viewport.candleWidth * 0.7);
    final wick = Paint()..strokeWidth = 1;
    final body = Paint();
    final volume = Paint();
    for (var i = start; i < end; i++) {
      final c = g.candles[i];
      final color = c.isUp ? theme.up : theme.down;
      final x = g.xOf(i);
      wick.color = color;
      canvas.drawLine(Offset(x, g.yOf(c.high)), Offset(x, g.yOf(c.low)), wick);
      final top = g.yOf(math.max(c.open, c.close));
      final bottom = g.yOf(math.min(c.open, c.close));
      body.color = color;
      canvas.drawRect(
        Rect.fromLTRB(
          x - bodyWidth / 2,
          top,
          x + bodyWidth / 2,
          math.max(bottom, top + 1),
        ),
        body,
      );
      final v = c.volume;
      if (showVolume && v != null && g.maxVolume > 0) {
        final h = g.volumeHeight * (v / g.maxVolume);
        volume.color = color.withValues(alpha: 0.35);
        canvas.drawRect(
          Rect.fromLTRB(
            x - bodyWidth / 2,
            g.plotHeight - h,
            x + bodyWidth / 2,
            g.plotHeight,
          ),
          volume,
        );
      }
    }
  }

  void _paintPriceAxis(Canvas canvas, PlotGeometry g) {
    final r = g.range;
    if (r == null) return;
    final grid = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;
    final step = ChartFormat.niceStep(r.max - r.min, 5);
    final digits = ChartFormat.priceDigits(r.max - r.min);
    var price = (r.min / step).ceil() * step;
    while (price <= r.max) {
      final y = g.yOf(price);
      canvas.drawLine(Offset(0, y), Offset(g.plotWidth, y), grid);
      final label = labels.layout(ChartFormat.price(price, digits));
      label.paint(canvas, Offset(g.plotWidth + 4, y - label.height / 2));
      price += step;
    }
  }

  void _paintTimeAxis(Canvas canvas, PlotGeometry g) {
    final total = g.candles.length;
    final (start, end) = viewport.visibleRange(total, g.plotWidth);
    if (start >= end) return;
    // One label every ~80 px, snapped to candle indices.
    final every = math.max(1, (80 / viewport.candleWidth).round());
    final y = g.plotHeight + 2;
    for (var i = (start / every).ceil() * every; i < end; i += every) {
      final label = labels.layout(
        ChartFormat.time(
          g.candles[i].openTime,
          interval.duration,
          local: localTime,
        ),
      );
      final x = g.xOf(i) - label.width / 2;
      if (x < 0 || x + label.width > g.plotWidth) continue;
      label.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(CandlePainter old) =>
      !identical(old.series, series) ||
      old.viewport != viewport ||
      old.theme != theme ||
      old.interval != interval ||
      old.showVolume != showVolume ||
      old.localTime != localTime;
}
