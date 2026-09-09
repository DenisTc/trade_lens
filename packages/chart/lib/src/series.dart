import 'dart:collection';

import 'package:chart/src/model.dart';

/// Ordered candles keyed by `openTime`. Immutable from the outside: every
/// change returns a new series, so painters can compare by identity.
final class CandleSeries {
  CandleSeries._(this._candles);

  /// Non-finite candles (NaN/Infinity from a broken source) are dropped:
  /// one bad value must not break the whole chart.
  factory CandleSeries.of(Iterable<ChartCandle> candles) {
    final sorted = candles.where(isFinite).toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));
    return CandleSeries._(_dedupe(sorted));
  }

  static bool isFinite(ChartCandle c) =>
      c.open.isFinite &&
      c.high.isFinite &&
      c.low.isFinite &&
      c.close.isFinite &&
      (c.volume?.isFinite ?? true);

  static final empty = CandleSeries._(const []);

  final List<ChartCandle> _candles;

  List<ChartCandle> get candles => UnmodifiableListView(_candles);
  int get length => _candles.length;
  bool get isEmpty => _candles.isEmpty;
  ChartCandle? get last => _candles.isEmpty ? null : _candles.last;
  ChartCandle operator [](int index) => _candles[index];

  /// A candle with an existing `openTime` replaces it (a live update of the
  /// current candle); a newer one is appended; an older gap-fill is
  /// inserted in order.
  CandleSeries upsert(ChartCandle candle) {
    if (!isFinite(candle)) return this;
    if (_candles.isEmpty) return CandleSeries._([candle]);
    final last = _candles.last;
    if (candle.openTime == last.openTime) {
      return CandleSeries._([..._candles.take(_candles.length - 1), candle]);
    }
    if (candle.openTime.isAfter(last.openTime)) {
      return CandleSeries._([..._candles, candle]);
    }
    final next = [..._candles];
    final index = next.indexWhere((c) => !c.openTime.isBefore(candle.openTime));
    if (next[index].openTime == candle.openTime) {
      next[index] = candle;
    } else {
      next.insert(index, candle);
    }
    return CandleSeries._(next);
  }

  CandleSeries upsertAll(Iterable<ChartCandle> batch) =>
      batch.fold(this, (series, candle) => series.upsert(candle));

  static List<ChartCandle> _dedupe(List<ChartCandle> sorted) {
    if (sorted.length < 2) return sorted;
    final out = <ChartCandle>[sorted.first];
    for (final c in sorted.skip(1)) {
      if (c.openTime == out.last.openTime) {
        out[out.length - 1] = c;
      } else {
        out.add(c);
      }
    }
    return out;
  }
}
