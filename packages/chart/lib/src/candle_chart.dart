import 'package:chart/src/axes.dart';
import 'package:chart/src/candle_painter.dart';
import 'package:chart/src/chart_theme.dart';
import 'package:chart/src/crosshair_painter.dart';
import 'package:chart/src/model.dart';
import 'package:chart/src/series.dart';
import 'package:chart/src/viewport.dart';
import 'package:flutter/material.dart';

/// Candlestick chart on two `CustomPainter`s.
///
/// - One finger pans, two fingers zoom around the focal point, a long
///   press (or hover on desktop) shows the crosshair and reports
///   [onCrosshair].
/// - The viewport follows new candles while the newest one is on screen;
///   panning into history stops following until the user returns.
/// - [showVolume] false and a custom [interval] label cover REST-only
///   sources with their own granularity and no volume.
class CandleChart extends StatefulWidget {
  const CandleChart({
    required this.series,
    required this.interval,
    super.key,
    this.showVolume = true,
    this.onCrosshair,
    this.theme,
    this.initialCandleWidth = 8,
    this.emptyLabel = 'No data',
    this.localTime = true,
  });

  final CandleSeries series;
  final ChartInterval interval;
  final bool showVolume;
  final ValueChanged<CrosshairInfo?>? onCrosshair;
  final CandleChartTheme? theme;
  final double initialCandleWidth;
  final String emptyLabel;

  /// Time axis in local time (default) or UTC (golden tests).
  final bool localTime;

  @override
  State<CandleChart> createState() => CandleChartState();
}

/// Public for widget tests: exposes the viewport.
class CandleChartState extends State<CandleChart> {
  late ChartViewport viewport = ChartViewport(
    firstIndex: 0,
    candleWidth: widget.initialCandleWidth,
  );
  CrosshairPosition? _crosshair;
  LabelCache? _labels;
  CandleChartTheme? _theme;
  double _plotWidth = 0;
  bool _following = true;
  ChartViewport? _scaleStart;
  Offset? _scaleFocal;

  ChartViewport get currentViewport => viewport;

  @override
  void didUpdateWidget(CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.series, widget.series) && _following) {
      viewport = viewport.stickToEnd(widget.series.length, _plotWidth);
    }
  }

  @override
  void dispose() {
    _labels?.dispose();
    super.dispose();
  }

  CandleChartTheme _resolveTheme(BuildContext context) {
    final theme = widget.theme ?? CandleChartTheme.of(context);
    if (theme != _theme) {
      _labels?.dispose();
      _labels = LabelCache(
        style: TextStyle(
          color: theme.axisText,
          fontSize: theme.axisTextSize,
          fontFamily: theme.fontFamily,
        ),
      );
      _theme = theme;
    }
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = constraints.maxWidth - theme.priceAxisWidth;
        if (plotWidth != _plotWidth) {
          _plotWidth = plotWidth;
          if (_following) {
            viewport = viewport.stickToEnd(widget.series.length, plotWidth);
          }
        }
        if (widget.series.isEmpty) {
          return Center(
            child: Text(
              widget.emptyLabel,
              style: TextStyle(color: theme.axisText),
            ),
          );
        }
        return MouseRegion(
          onHover: (e) => _setCrosshair(e.localPosition),
          onExit: (_) => _setCrosshair(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: (_) => _scaleStart = null,
            onLongPressStart: (d) => _setCrosshair(d.localPosition),
            onLongPressMoveUpdate: (d) => _setCrosshair(d.localPosition),
            onLongPressEnd: (_) => _setCrosshair(null),
            child: CustomPaint(
              key: const Key('candle_chart_paint'),
              painter: CandlePainter(
                series: widget.series,
                viewport: viewport,
                theme: theme,
                interval: widget.interval,
                labels: _labels!,
                showVolume: widget.showVolume,
                localTime: widget.localTime,
              ),
              foregroundPainter: CrosshairPainter(
                series: widget.series,
                viewport: viewport,
                theme: theme,
                interval: widget.interval,
                labels: _labels!,
                position: _crosshair,
                showVolume: widget.showVolume,
                localTime: widget.localTime,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStart = viewport;
    _scaleFocal = d.localFocalPoint;
    _setCrosshair(null);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _scaleStart;
    final focal = _scaleFocal;
    if (start == null || focal == null) return;
    final total = widget.series.length;
    var next = start;
    if (d.pointerCount > 1 || d.scale != 1) {
      next = next.zoomAt(d.scale, focal.dx, total, _plotWidth);
    }
    next = next.pan(d.localFocalPoint.dx - focal.dx, total, _plotWidth);
    setState(() {
      viewport = next;
      _following = next.isAtEnd(total, _plotWidth);
    });
  }

  void _setCrosshair(Offset? local) {
    final next = local == null ? null : CrosshairPosition(local);
    if (next == _crosshair) return;
    setState(() => _crosshair = next);
    final callback = widget.onCrosshair;
    if (callback == null) return;
    if (local == null) {
      callback(null);
      return;
    }
    final index = viewport.indexAt(local.dx, widget.series.length);
    if (index == null) {
      callback(null);
      return;
    }
    final geometry = PlotGeometry(
      size: Size(
        _plotWidth + (_theme?.priceAxisWidth ?? 0),
        context.size?.height ?? 0,
      ),
      theme: _theme!,
      viewport: viewport,
      candles: widget.series.candles,
      showVolume: widget.showVolume,
    );
    callback(
      CrosshairInfo(
        candle: widget.series[index],
        index: index,
        price: geometry.priceAt(local.dy.clamp(0, geometry.priceHeight)),
      ),
    );
  }
}
