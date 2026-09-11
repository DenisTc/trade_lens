import 'package:chart/chart.dart';
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

  test('a long series does not drift: the running sum stays exact', () {
    // 1, 2, 1, 2, … a hundred thousand times; every window of 2 averages 1.5.
    final many = [for (var i = 0; i < 100000; i++) candle(i, 1.0 + i % 2)];
    const ma = MovingAverage(period: 2, color: Colors.white);

    expect(ma.compute(many).last, closeTo(1.5, 1e-9));
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
