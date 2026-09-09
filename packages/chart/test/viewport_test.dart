import 'package:chart/chart.dart';
import 'package:flutter_test/flutter_test.dart';

ChartCandle _c(int minute, {double close = 10, double? volume = 1}) =>
    ChartCandle(
      openTime: DateTime.utc(2026, 9, 9, 12, minute),
      open: 10,
      high: close + 1,
      low: 9,
      close: close,
      volume: volume,
    );

void main() {
  group('CandleSeries', () {
    test('of() sorts and dedupes by openTime, last wins', () {
      final series = CandleSeries.of([_c(2), _c(0), _c(2, close: 20), _c(1)]);
      expect(series.candles.map((c) => c.openTime.minute), [0, 1, 2]);
      expect(series[2].close, 20);
    });

    test('upsert replaces the same openTime and appends newer', () {
      var series = CandleSeries.of([_c(0), _c(1)]);
      series = series.upsert(_c(1, close: 15));
      expect(series.length, 2);
      expect(series.last!.close, 15);
      series = series.upsert(_c(2));
      expect(series.length, 3);
      expect(series.last!.openTime.minute, 2);
    });

    test('upsert inserts a gap-fill candle in order', () {
      final series = CandleSeries.of([_c(0), _c(3)]).upsertAll([_c(2), _c(1)]);
      expect(series.candles.map((c) => c.openTime.minute), [0, 1, 2, 3]);
    });

    test('each mutation is a new instance', () {
      final a = CandleSeries.of([_c(0)]);
      final b = a.upsert(_c(0, close: 11));
      expect(identical(a, b), isFalse);
      expect(a.last!.close, 10);
    });
  });

  group('ChartViewport', () {
    const plot = 300.0;
    final candles = [for (var i = 0; i < 100; i++) _c(i)];

    test('stickToEnd shows the newest candles with right padding', () {
      const vp = ChartViewport(firstIndex: 0, candleWidth: 10);
      final stuck = vp.stickToEnd(100, plot);
      expect(stuck.firstIndex, 100 + 2 - 30);
      expect(stuck.isAtEnd(100, plot), isTrue);
      expect(vp.isAtEnd(100, plot), isFalse);
    });

    test('zoom keeps the candle under the focal point in place', () {
      const vp = ChartViewport(firstIndex: 20, candleWidth: 10);
      const focalX = 150.0;
      final before = vp.firstIndex + focalX / vp.candleWidth;
      final zoomed = vp.zoomAt(2, focalX, 100, plot);
      expect(zoomed.candleWidth, 20);
      expect(
        zoomed.firstIndex + focalX / zoomed.candleWidth,
        closeTo(before, 1e-9),
      );
    });

    test('zoom is clamped to min/max width', () {
      const vp = ChartViewport(firstIndex: 0, candleWidth: 10);
      expect(vp.zoomAt(100, 0, 100, plot).candleWidth, 40);
      expect(vp.zoomAt(0.01, 0, 100, plot).candleWidth, 2);
    });

    test('pan moves by pixels and clamps to the series', () {
      const vp = ChartViewport(firstIndex: 50, candleWidth: 10);
      expect(vp.pan(100, 100, plot).firstIndex, 40);
      expect(vp.pan(-100, 100, plot).firstIndex, 60);
      expect(
        vp.pan(10000, 100, plot).firstIndex,
        0,
        reason: 'cannot pan before start',
      );
      expect(
        vp.pan(-10000, 100, plot).firstIndex,
        100 + 2 - 30,
        reason: 'stops at the right padding',
      );
    });

    test('priceRange covers visible candles with 5 % headroom', () {
      const vp = ChartViewport(firstIndex: 0, candleWidth: 30); // 10 visible
      final range = vp.priceRange(candles, plot)!;
      expect(range.min, lessThan(9));
      expect(range.max, greaterThan(11));
      expect(vp.priceRange(const [], plot), isNull);
    });

    test('indexAt / xOf round-trip', () {
      const vp = ChartViewport(firstIndex: 5, candleWidth: 10);
      expect(vp.indexAt(vp.xOf(7), 100), 7);
      expect(vp.indexAt(-1, 100), isNull);
    });

    test('maxVolume ignores candles without volume', () {
      const vp = ChartViewport(firstIndex: 0, candleWidth: 10);
      expect(vp.maxVolume([_c(0, volume: null), _c(1, volume: 3)], plot), 3);
    });
  });
}
