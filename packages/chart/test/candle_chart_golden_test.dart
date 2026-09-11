@Tags(['golden'])
library;

import 'package:chart/chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

/// Three states from the spec (empty, 50 candles, 500 candles with the
/// crosshair) in light and dark theme. Regenerate with
/// `fvm flutter test --update-goldens --tags golden`.
void main() {
  Widget host(Widget child, {required Brightness brightness}) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3A56C7),
        brightness: brightness,
      ),
      useMaterial3: true,
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 240, child: child)),
    ),
  );

  for (final brightness in Brightness.values) {
    final suffix = brightness.name;

    testWidgets('empty · $suffix', (tester) async {
      await tester.pumpWidget(
        host(
          CandleChart(series: CandleSeries.empty, interval: ChartInterval.m1),
          brightness: brightness,
        ),
      );
      await expectLater(
        find.byType(CandleChart),
        matchesGoldenFile('goldens/candle_chart_empty_$suffix.png'),
      );
    });

    testWidgets('200 candles with MA7 and EMA25 · $suffix', (tester) async {
      await tester.pumpWidget(
        host(
          CandleChart(
            series: CandleSeries.of(syntheticCandles(200)),
            interval: ChartInterval.m1,
            localTime: false,
            overlays: const [
              MovingAverage(period: 7, color: Color(0xFFF2B94A)),
              MovingAverage(
                period: 25,
                color: Color(0xFF4AA3F2),
                exponential: true,
              ),
            ],
          ),
          brightness: brightness,
        ),
      );
      await expectLater(
        find.byType(CandleChart),
        matchesGoldenFile('goldens/candle_chart_200_ma_$suffix.png'),
      );
    });

    testWidgets('50 candles with volume · $suffix', (tester) async {
      await tester.pumpWidget(
        host(
          CandleChart(
            series: CandleSeries.of(syntheticCandles(50)),
            interval: ChartInterval.m1,
            localTime: false,
          ),
          brightness: brightness,
        ),
      );
      await expectLater(
        find.byType(CandleChart),
        matchesGoldenFile('goldens/candle_chart_50_$suffix.png'),
      );
    });

    testWidgets(
      '500 candles, crosshair, no volume (auto granularity) · $suffix',
      (tester) async {
        await tester.pumpWidget(
          host(
            CandleChart(
              series: CandleSeries.of(syntheticCandles(500, withVolume: false)),
              interval: const ChartInterval(
                Duration(minutes: 30),
                label: '30m',
              ),
              showVolume: false,
              initialCandleWidth: 4,
              localTime: false,
            ),
            brightness: brightness,
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('candle_chart_paint'))),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await expectLater(
          find.byType(CandleChart),
          matchesGoldenFile('goldens/candle_chart_500_crosshair_$suffix.png'),
        );
        await gesture.up();
      },
    );
  }
}
