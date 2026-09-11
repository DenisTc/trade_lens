import 'dart:async';

import 'package:chart/src/axes.dart';
import 'package:chart/src/candle_painter.dart';
import 'package:chart/src/chart_theme.dart';
import 'package:chart/src/crosshair_painter.dart';
import 'package:chart/src/indicators.dart';
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
    this.overlays = const [],
    this.showVolume = true,
    this.onCrosshair,
    this.onReachStart,
    this.theme,
    this.initialCandleWidth = 8,
    this.emptyLabel = 'No data',
    this.localTime = true,
  });

  final CandleSeries series;
  final ChartInterval interval;

  /// Moving averages drawn over the candles, in this order.
  final List<MovingAverage> overlays;

  /// Called when a pan brings the oldest candles near the left edge: the
  /// owner may prepend history and returns when it is done or gave up.
  /// Not called again for the same oldest candle while the returned
  /// future is pending; once it completes, a further pan asks again, so
  /// a failed page is retried and a page with nothing older costs one
  /// cheap call. Candles that arrive in front shift the viewport by their
  /// count, so what was under the finger stays there.
  final Future<void> Function()? onReachStart;
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
  LabelCache? _crosshairLabels;
  CandleChartTheme? _theme;
  double _plotWidth = 0;
  bool _following = true;
  ChartViewport? _scaleStart;
  Offset? _scaleFocal;

  ChartViewport get currentViewport => viewport;

  /// The oldest candle a pending [CandleChart.onReachStart] was asked for.
  DateTime? _asking;

  @override
  void didUpdateWidget(CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.series, widget.series)) return;
    if (_following) {
      viewport = viewport.stickToEnd(widget.series.length, _plotWidth);
      return;
    }
    final prepended = _prependedCount(oldWidget.series, widget.series);
    if (prepended > 0) {
      viewport = viewport.copyWith(firstIndex: viewport.firstIndex + prepended);
      // A gesture in progress is measured from its own origin; shifted
      // too, or its next update would undo the shift under the finger.
      _scaleStart = _scaleStart?.copyWith(
        firstIndex: _scaleStart!.firstIndex + prepended,
      );
    }
  }

  /// How many candles [next] has in front of the first candle of [old].
  static int _prependedCount(CandleSeries old, CandleSeries next) {
    final first = old.last == null ? null : old[0].openTime;
    if (first == null) return 0;
    var n = 0;
    while (n < next.length && next[n].openTime.isBefore(first)) {
      n++;
    }
    return n;
  }

  @override
  void dispose() {
    _labels?.dispose();
    _crosshairLabels?.dispose();
    super.dispose();
  }

  CandleChartTheme _resolveTheme(BuildContext context) {
    final theme = widget.theme ?? CandleChartTheme.of(context);
    if (theme != _theme) {
      _labels?.dispose();
      _crosshairLabels?.dispose();
      _labels = LabelCache(
        style: TextStyle(
          color: theme.axisText,
          fontSize: theme.axisTextSize,
          fontFamily: theme.fontFamily,
        ),
      );
      _crosshairLabels = LabelCache(
        style: TextStyle(
          color: theme.crosshairLabelText,
          fontSize: theme.axisTextSize,
          fontFamily: theme.fontFamily,
        ),
      );
      _theme = theme;
    }
    return theme;
  }

  OverlaySet _overlaySet = OverlaySet.empty;

  /// The averages for the current series, recomputed only when the
  /// series instance or the overlay list changes — never on a pan.
  OverlaySet _resolveOverlays() {
    if (!_overlaySet.matches(widget.series, widget.overlays)) {
      _overlaySet = widget.overlays.isEmpty
          ? OverlaySet.empty
          : OverlaySet(widget.series, widget.overlays);
    }
    return _overlaySet;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme(context);
    final overlays = _resolveOverlays();
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
            // Two render objects, each behind its own repaint boundary:
            // moving the crosshair repaints only the top layer. A single
            // CustomPaint with a foregroundPainter would repaint both.
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    key: const Key('candle_chart_paint'),
                    painter: CandlePainter(
                      series: widget.series,
                      viewport: viewport,
                      theme: theme,
                      interval: widget.interval,
                      labels: _labels!,
                      overlays: overlays,
                      showVolume: widget.showVolume,
                      localTime: widget.localTime,
                    ),
                    size: Size.infinite,
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    key: const Key('candle_chart_crosshair'),
                    painter: CrosshairPainter(
                      series: widget.series,
                      viewport: viewport,
                      theme: theme,
                      interval: widget.interval,
                      labels: _labels!,
                      crosshairLabels: _crosshairLabels!,
                      position: _crosshair,
                      overlays: overlays,
                      showVolume: widget.showVolume,
                      localTime: widget.localTime,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ],
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
    final next = start.transformed(
      factor: d.scale,
      focalX: focal.dx,
      dx: d.localFocalPoint.dx - focal.dx,
      total: total,
      plotWidth: _plotWidth,
    );
    setState(() {
      viewport = next;
      _following = next.isAtEnd(total, _plotWidth);
    });
    // Ask a screen's width ahead of the edge, so the page is there before
    // the pan runs out of candles.
    final callback = widget.onReachStart;
    final oldest = total == 0 ? null : widget.series[0].openTime;
    if (callback != null &&
        oldest != null &&
        _asking == null &&
        next.firstIndex < next.visibleCount(_plotWidth)) {
      _asking = oldest;
      unawaited(
        callback().whenComplete(() {
          if (mounted && _asking == oldest) _asking = null;
        }),
      );
    }
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
    final index = viewport.indexAt(
      local.dx,
      widget.series.length,
      plotWidth: _plotWidth,
    );
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
