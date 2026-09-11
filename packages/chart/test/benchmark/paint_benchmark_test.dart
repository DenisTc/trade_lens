import 'dart:ui' as ui;

import 'package:chart/chart.dart';
import 'package:chart/src/axes.dart';
import 'package:chart/src/candle_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Argument for the 60 FPS claim: painting 500 candles at a typical phone
/// width must stay far below one frame. Prints the mean so CI logs keep a
/// history; the assertion is loose enough for slow runners.
void main() {
  test('painting 500 candles stays under a frame budget', () {
    final series = CandleSeries.of(syntheticCandles(500));
    const theme = CandleChartTheme(
      up: Colors.green,
      down: Colors.red,
      grid: Colors.grey,
      axisText: Colors.black,
      crosshair: Colors.black,
      crosshairLabelBackground: Colors.black,
      crosshairLabelText: Colors.white,
    );
    final labels = LabelCache(style: const TextStyle(fontSize: 10));
    const size = Size(390, 300);
    final viewport = const ChartViewport(
      firstIndex: 0,
      candleWidth: 3,
    ).stickToEnd(500, size.width - theme.priceAxisWidth);
    final painter = CandlePainter(
      series: series,
      viewport: viewport,
      theme: theme,
      interval: ChartInterval.m1,
      labels: labels,
      // The averages ride along: a pan repaints them too.
      overlays: OverlaySet(series, const [
        MovingAverage(period: 7, color: Colors.orange),
        MovingAverage(period: 25, color: Colors.blue, exponential: true),
      ]),
      localTime: false,
    );

    // Warm-up fills the label cache like a real first frame would.
    _paintOnce(painter, size);
    const runs = 100;
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      _paintOnce(painter, size);
    }
    stopwatch.stop();
    final mean = stopwatch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print, benchmark output belongs in the log
    print(
      'CandlePainter: 500 candles, mean ${mean.toStringAsFixed(3)} ms over $runs paints',
    );
    expect(mean, lessThan(16), reason: 'one frame at 60 FPS');
    labels.dispose();
  });
}

void _paintOnce(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  recorder.endRecording().dispose();
}
