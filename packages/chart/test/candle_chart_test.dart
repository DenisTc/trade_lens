import 'dart:async';

import 'package:chart/chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  const size = Size(400, 300);

  Future<CandleChartState> pumpChart(
    WidgetTester tester,
    CandleSeries series, {
    ValueChanged<CrosshairInfo?>? onCrosshair,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: size,
            child: CandleChart(
              series: series,
              interval: ChartInterval.m1,
              onCrosshair: onCrosshair,
            ),
          ),
        ),
      ),
    );
    return tester.state(find.byType(CandleChart));
  }

  testWidgets('starts stuck to the newest candles', (tester) async {
    final state = await pumpChart(
      tester,
      CandleSeries.of(syntheticCandles(200)),
    );
    final plotWidth =
        size.width -
        CandleChartTheme.of(tester.element(find.byType(CandleChart)))
            .priceAxisWidth;
    expect(state.currentViewport.isAtEnd(200, plotWidth), isTrue);
  });

  testWidgets('dragging pans into history and stops following', (tester) async {
    final series = CandleSeries.of(syntheticCandles(200));
    final state = await pumpChart(tester, series);
    final before = state.currentViewport.firstIndex;

    await tester.drag(
      find.byKey(const Key('candle_chart_paint')),
      const Offset(120, 0),
    );
    await tester.pump();
    expect(state.currentViewport.firstIndex, lessThan(before));

    // A new candle arrives: the viewport must not jump back to the end.
    final panned = state.currentViewport.firstIndex;
    await pumpChart(tester, series.upsert(syntheticCandles(201).last));
    expect(state.currentViewport.firstIndex, panned);
  });

  testWidgets('panning near the start asks for history once per series', (
    tester,
  ) async {
    final series = CandleSeries.of(syntheticCandles(60));
    var asked = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: size,
            child: CandleChart(
              series: series,
              interval: ChartInterval.m1,
              onReachStart: () {
                asked++;
                return pending.future;
              },
            ),
          ),
        ),
      ),
    );
    final paint = find.byKey(const Key('candle_chart_paint'));

    await tester.drag(paint, const Offset(200, 0));
    await tester.pump();
    await tester.drag(paint, const Offset(200, 0));
    await tester.pump();
    // Two pans to the edge, one request: the first is still pending.
    expect(asked, 1);

    // The request gave up with nothing new; a further pan tries again.
    pending.complete();
    await tester.pump();
    await tester.drag(paint, const Offset(50, 0));
    await tester.pump();
    expect(asked, 2);
  });

  testWidgets('history landing mid-drag does not jump under the finger', (
    tester,
  ) async {
    final recent = syntheticCandles(300).sublist(200);
    final series = CandleSeries.of(recent);
    final state = await pumpChart(tester, series);
    final paint = find.byKey(const Key('candle_chart_paint'));

    // Off the end first, so the chart is not following; then a finger
    // that stays down. The recogniser spends the first move on its slop.
    await tester.drag(paint, const Offset(100, 0));
    await tester.pump();
    final finger = await tester.startGesture(tester.getCenter(paint));
    await finger.moveBy(const Offset(20, 0));
    await tester.pump();
    await finger.moveBy(const Offset(20, 0));
    await tester.pump();
    final underFinger = series[state.currentViewport.firstIndex.round()];

    // Two hundred older candles arrive while the finger is still down.
    final withHistory = CandleSeries.of(syntheticCandles(300));
    await pumpChart(tester, withHistory);
    await finger.moveBy(const Offset(10, 0));
    await tester.pump();
    await finger.up();

    final now = withHistory[state.currentViewport.firstIndex.round()];
    // Ten pixels is a candle or so; two hundred candles is a jump.
    expect(
      now.openTime.difference(underFinger.openTime).inMinutes.abs(),
      lessThan(5),
    );
  });

  testWidgets('a new candle keeps the chart at the end while following', (
    tester,
  ) async {
    final series = CandleSeries.of(syntheticCandles(200));
    final state = await pumpChart(tester, series);
    final before = state.currentViewport.firstIndex;
    await pumpChart(tester, series.upsert(syntheticCandles(201).last));
    expect(state.currentViewport.firstIndex, before + 1);
  });

  testWidgets('pinch zoom changes the candle width', (tester) async {
    final state = await pumpChart(
      tester,
      CandleSeries.of(syntheticCandles(200)),
    );
    final before = state.currentViewport.candleWidth;
    final center = tester.getCenter(
      find.byKey(const Key('candle_chart_paint')),
    );

    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();

    expect(state.currentViewport.candleWidth, greaterThan(before));
  });

  testWidgets('long press reports the candle under the finger', (tester) async {
    CrosshairInfo? info;
    final series = CandleSeries.of(syntheticCandles(50));
    await pumpChart(tester, series, onCrosshair: (i) => info = i);
    final paint = find.byKey(const Key('candle_chart_paint'));

    final gesture = await tester.startGesture(tester.getCenter(paint));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(info, isNotNull);
    expect(series.candles, contains(info!.candle));

    await gesture.up();
    await tester.pump();
    expect(info, isNull);
  });

  testWidgets('empty series shows the empty label', (tester) async {
    await pumpChart(tester, CandleSeries.empty);
    expect(find.text('No data'), findsOneWidget);
  });

  test('ChartFormat.timeFull shows the day and, below daily, the time', () {
    final t = DateTime.utc(2026, 9, 9, 14, 30);
    expect(
      ChartFormat.timeFull(t, const Duration(hours: 1), local: false),
      '09.09 14:30',
    );
    expect(
      ChartFormat.timeFull(t, const Duration(days: 1), local: false),
      '09.09',
    );
  });

  test('ChartFormat picks digits and nice steps from the range', () {
    expect(ChartFormat.priceDigits(5000), 0);
    expect(ChartFormat.priceDigits(50), 1);
    expect(ChartFormat.priceDigits(0.5), 3);
    expect(ChartFormat.niceStep(1000, 5), 200);
    expect(ChartFormat.niceStep(7, 5), 2);
    expect(
      ChartFormat.time(
        DateTime.utc(2026, 9, 9, 12, 30),
        const Duration(minutes: 1),
      ),
      isNotEmpty,
    );
  });
}
