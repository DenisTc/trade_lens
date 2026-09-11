import 'package:chart/chart.dart';
import 'package:chart/src/candle_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChartCandle candle(int i, double close) => ChartCandle(
  openTime: DateTime.utc(2026, 9, 9, 12, i),
  open: close,
  high: close + 1,
  low: close - 1,
  close: close,
);

void main() {
  const closes = <double>[1, 2, 3, 4, 5, 6];
  final candles = [for (final (i, c) in closes.indexed) candle(i, c)];

  test('a simple average starts once there are enough closes', () {
    const ma = MovingAverage(period: 3, color: Colors.white);

    expect(ma.compute(candles), [null, null, 2.0, 3.0, 4.0, 5.0]);
  });

  test('an exponential average is seeded with the first simple one', () {
    const ema = MovingAverage(
      period: 3,
      color: Colors.white,
      exponential: true,
    );
    final values = ema.compute(candles);

    expect(values.sublist(0, 3), [null, null, 2.0]);
    // k = 2 / (3 + 1) = 0.5: each step is half-way to the new close.
    expect(values[3], closeTo(3.0, 1e-9));
    expect(values[4], closeTo(4.0, 1e-9));
  });

  test('fewer candles than the period yields nothing, not a guess', () {
    const ma = MovingAverage(period: 10, color: Colors.white);

    expect(ma.compute(candles), everyElement(isNull));
    expect(ma.compute(const []), isEmpty);
  });

  test('a long series does not drift: the running sum matches a fresh one', () {
    // Awkward decimals for a hundred thousand candles; the last window is
    // then averaged the slow way, from scratch.
    final many = [
      for (var i = 0; i < 100000; i++) candle(i, 100 + (i * 0.37) % 7.3),
    ];
    const ma = MovingAverage(period: 25, color: Colors.white);
    final fresh =
        many
            .skip(many.length - 25)
            .map((c) => c.close)
            .reduce((a, b) => a + b) /
        25;

    expect(ma.compute(many).last, closeTo(fresh, 1e-9));
  });

  test('the price range widens so a trailing average stays on the plot', () {
    // Prices halve, then only the low candles are visible: the slow
    // average still sits up where the old prices were.
    final series = CandleSeries.of([
      for (var i = 0; i < 40; i++) candle(i, i < 20 ? 200 : 100),
    ]);
    const ema = MovingAverage(
      period: 25,
      color: Colors.white,
      exponential: true,
    );
    final overlays = OverlaySet(series, const [ema]);
    const viewport = ChartViewport(candleWidth: 10, firstIndex: 25);
    const theme = CandleChartTheme(
      up: Colors.green,
      down: Colors.red,
      grid: Colors.grey,
      axisText: Colors.grey,
      crosshair: Colors.white,
      crosshairLabelBackground: Colors.white,
      crosshairLabelText: Colors.black,
    );

    final g = PlotGeometry(
      size: const Size(200, 200),
      theme: theme,
      viewport: viewport,
      candles: series.candles,
      showVolume: false,
      overlays: overlays,
    );
    final value = overlays.values.single[30]!;

    expect(value, greaterThan(101));
    expect(g.yOf(value), inInclusiveRange(0, g.priceHeight));
  });

  test('the legend names the kind and the period', () {
    expect(const MovingAverage(period: 7, color: Colors.white).label, 'MA7');
    expect(
      const MovingAverage(
        period: 25,
        color: Colors.white,
        exponential: true,
      ).label,
      'EMA25',
    );
  });

  testWidgets('overlays are painted and repainted when they change', (
    tester,
  ) async {
    final series = CandleSeries.of([
      for (var i = 0; i < 30; i++) candle(i, 100 + (i % 5).toDouble()),
    ]);
    Widget chart(List<MovingAverage> overlays) => MaterialApp(
      home: SizedBox(
        width: 300,
        height: 200,
        child: CandleChart(
          series: series,
          interval: ChartInterval.m1,
          overlays: overlays,
        ),
      ),
    );

    await tester.pumpWidget(chart(const []));
    final paint = find.byKey(const Key('candle_chart_paint'));
    final before = tester.widget<CustomPaint>(paint).painter;

    await tester.pumpWidget(
      chart(const [MovingAverage(period: 7, color: Colors.amber)]),
    );
    final after = tester.widget<CustomPaint>(paint).painter!;

    expect(after.shouldRepaint(before!), isTrue);
    expect(tester.takeException(), isNull);
  });
}
