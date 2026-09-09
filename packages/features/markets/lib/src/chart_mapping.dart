import 'package:chart/chart.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chart_mapping.g.dart';

/// The one place where `Decimal` becomes `double`: the chart boundary.
ChartCandle toChartCandle(Candle c) => ChartCandle(
  openTime: c.openTime,
  open: c.open.toDouble(),
  high: c.high.toDouble(),
  low: c.low.toDouble(),
  close: c.close.toDouble(),
  volume: c.volume?.toDouble(),
);

/// Series for the chart. A live tick changes one candle in a 500-candle
/// list; converting and sorting everything again per tick would grow with
/// the history, so the previous series is reused and only the changed
/// tail is upserted.
@riverpod
class ChartSeries extends _$ChartSeries {
  List<Candle>? _lastCandles;
  CandleSeries? _lastSeries;

  @override
  AsyncValue<CandleSeries> build(Instrument instrument, Interval interval) {
    return ref.watch(candlesProvider(instrument, interval)).whenData((candles) {
      final series = incrementalSeries(_lastCandles, _lastSeries, candles);
      _lastCandles = candles;
      _lastSeries = series;
      return series;
    });
  }
}

/// Reuses [previousSeries] when [next] shares its prefix with [previous]
/// (same candle instances), upserting only the differing tail. Falls back
/// to a full rebuild when the lists diverge earlier or shrink.
CandleSeries incrementalSeries(
  List<Candle>? previous,
  CandleSeries? previousSeries,
  List<Candle> next,
) {
  if (previous == null ||
      previousSeries == null ||
      next.length < previous.length) {
    return CandleSeries.of(next.map(toChartCandle));
  }
  var shared = 0;
  while (shared < previous.length &&
      identical(previous[shared], next[shared])) {
    shared++;
  }
  // Only the last few candles may differ (live update, backfill append).
  if (previous.length - shared > 2) {
    return CandleSeries.of(next.map(toChartCandle));
  }
  var series = previousSeries;
  for (var i = shared; i < next.length; i++) {
    series = series.upsert(toChartCandle(next[i]));
  }
  return series;
}

/// Axis interval: the requested one, or the granularity the source actually
/// returned for `auto` (CoinGecko picks 30 min / 4 h / 4 d by range).
ChartInterval chartIntervalFor(Interval interval, List<Candle> candles) {
  final fixed = interval.duration;
  if (fixed != null) return ChartInterval(fixed, label: interval.code);
  final granularity = candles.granularity ?? const Duration(minutes: 30);
  return ChartInterval(granularity, label: '${_short(granularity)} · auto');
}

String _short(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d';
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${d.inMinutes}m';
}
