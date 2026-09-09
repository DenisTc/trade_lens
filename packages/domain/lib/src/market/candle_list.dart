import 'package:domain/src/market/candle.dart';

/// Pure list operations on candles ordered by `openTime`.
extension CandleListX on List<Candle> {
  /// Returns a new list where [candle] replaced the one with the same
  /// `openTime`, was appended if newer, or inserted in order otherwise.
  List<Candle> upsert(Candle candle) {
    if (isEmpty) return [candle];
    final lastOpen = last.openTime;
    if (candle.openTime == lastOpen) return [...take(length - 1), candle];
    if (candle.openTime.isAfter(lastOpen)) return [...this, candle];
    final next = [...this];
    final index = next.indexWhere((c) => !c.openTime.isBefore(candle.openTime));
    if (next[index].openTime == candle.openTime) {
      next[index] = candle;
    } else {
      next.insert(index, candle);
    }
    return next;
  }

  /// Median spacing between consecutive candles; the granularity a source
  /// with `Interval.auto` actually returned. Null for fewer than two.
  Duration? get granularity {
    if (length < 2) return null;
    final gaps = [
      for (var i = 1; i < length; i++)
        this[i].openTime.difference(this[i - 1].openTime),
    ]..sort();
    return gaps[gaps.length ~/ 2];
  }
}
