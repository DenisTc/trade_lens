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

/// Series for the chart, rebuilt only when the candle list changes.
@riverpod
AsyncValue<CandleSeries> chartSeries(
  Ref ref,
  Instrument instrument,
  Interval interval,
) {
  return ref
      .watch(candlesProvider(instrument, interval))
      .whenData((candles) => CandleSeries.of(candles.map(toChartCandle)));
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
