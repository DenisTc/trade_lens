import 'package:chart/src/axes.dart';
import 'package:chart/src/candle_painter.dart';
import 'package:chart/src/chart_theme.dart';
import 'package:chart/src/model.dart';
import 'package:chart/src/series.dart';
import 'package:chart/src/viewport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Where the user is pointing, in plot pixels; null hides the crosshair.
@immutable
final class CrosshairPosition {
  const CrosshairPosition(this.offset);

  final Offset offset;

  @override
  bool operator ==(Object other) =>
      other is CrosshairPosition && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

/// What the crosshair is over, reported to the host through `onCrosshair`.
@immutable
final class CrosshairInfo {
  const CrosshairInfo({
    required this.candle,
    required this.index,
    required this.price,
  });

  final ChartCandle candle;
  final int index;

  /// Price under the pointer (not the candle's close).
  final double price;
}

/// Separate layer: moving the finger repaints only this painter, the
/// candles behind it stay cached.
final class CrosshairPainter extends CustomPainter {
  CrosshairPainter({
    required this.series,
    required this.viewport,
    required this.theme,
    required this.interval,
    required this.labels,
    required this.crosshairLabels,
    required this.position,
    this.showVolume = true,
    this.localTime = true,
  });

  final CandleSeries series;
  final ChartViewport viewport;
  final CandleChartTheme theme;
  final ChartInterval interval;
  final LabelCache labels;

  /// Laid out in the label colour of the crosshair; cached like the axis
  /// labels so hover does not re-shape text every frame.
  final LabelCache crosshairLabels;
  final CrosshairPosition? position;
  final bool showVolume;
  final bool localTime;

  @override
  void paint(Canvas canvas, Size size) {
    final p = position;
    if (p == null) return;
    final g = PlotGeometry(
      size: size,
      theme: theme,
      viewport: viewport,
      candles: series.candles,
      showVolume: showVolume,
    );
    if (p.offset.dx >= g.plotWidth || p.offset.dy > g.plotHeight) return;
    final index = g.indexAt(p.offset.dx);
    if (index == null || g.range == null) return;
    final candle = series[index];
    final x = g.xOf(index);
    final y = p.offset.dy.clamp(0.0, g.priceHeight);

    final line = Paint()
      ..color = theme.crosshair
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(x, 0), Offset(x, g.plotHeight), line)
      ..drawLine(Offset(0, y), Offset(g.plotWidth, y), line);

    final digits = ChartFormat.priceDigits(g.range!.max - g.range!.min);
    _label(
      canvas,
      ChartFormat.price(g.priceAt(y), digits),
      Offset(g.plotWidth + 2, y),
      alignLeft: true,
    );
    _label(
      canvas,
      ChartFormat.time(candle.openTime, interval.duration, local: localTime),
      Offset(x, g.plotHeight + 1),
      centered: true,
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignLeft = false,
    bool centered = false,
  }) {
    final painter = crosshairLabels.layout(text);
    final left = centered
        ? anchor.dx - painter.width / 2
        : alignLeft
        ? anchor.dx
        : anchor.dx - painter.width;
    final top = centered ? anchor.dy : anchor.dy - painter.height / 2;
    final rect = Rect.fromLTWH(
      left - 3,
      top - 1,
      painter.width + 6,
      painter.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = theme.crosshairLabelBackground,
    );
    painter.paint(canvas, Offset(left, top));
  }

  @override
  bool shouldRepaint(CrosshairPainter old) =>
      old.position != position ||
      !identical(old.series, series) ||
      old.viewport != viewport ||
      old.theme != theme;
}
