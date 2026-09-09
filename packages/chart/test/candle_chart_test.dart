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
