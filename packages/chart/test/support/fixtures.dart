import 'dart:math';

import 'package:chart/chart.dart';

/// Deterministic random-walk candles so goldens and benchmarks are stable.
List<ChartCandle> syntheticCandles(
  int count, {
  int seed = 42,
  bool withVolume = true,
  Duration step = const Duration(minutes: 1),
}) {
  final random = Random(seed);
  var price = 100.0;
  final start = DateTime.utc(2026, 9, 9, 12);
  return [
    for (var i = 0; i < count; i++)
      () {
        final open = price;
        final drift = (random.nextDouble() - 0.5) * 2;
        final close = open + drift;
        final high = max(open, close) + random.nextDouble();
        final low = min(open, close) - random.nextDouble();
        price = close;
        return ChartCandle(
          openTime: start.add(step * i),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: withVolume ? 10 + random.nextDouble() * 90 : null,
        );
      }(),
  ];
}
