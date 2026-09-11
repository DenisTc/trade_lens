import 'dart:collection';

import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// The bookkeeping Binance's partial stream spared us: Bybit's book
/// arrives as one snapshot and then deltas, where a level with size zero
/// is gone and a level not mentioned is unchanged. Sequence numbers must
/// climb; one that does not means a frame was lost, and the book is
/// untrustworthy until the next snapshot.
final class BybitOrderBook {
  BybitOrderBook({this.depth = 10});

  /// Levels handed out per side.
  final int depth;

  final SplayTreeMap<Decimal, Decimal> _bids = SplayTreeMap(
    (a, b) => b.compareTo(a), // best bid first
  );
  final SplayTreeMap<Decimal, Decimal> _asks = SplayTreeMap();
  int? _sequence;
  bool _valid = false;

  /// Whether a snapshot has been seen and every delta since was in order.
  bool get isValid => _valid;

  void applySnapshot(
    List<OrderBookLevel> bids,
    List<OrderBookLevel> asks, {
    required int sequence,
  }) {
    _bids.clear();
    _asks.clear();
    _put(_bids, bids);
    _put(_asks, asks);
    _sequence = sequence;
    _valid = true;
  }

  /// Applies a delta; returns false, and marks the book invalid, when
  /// [sequence] does not follow the last one.
  bool applyDelta(
    List<OrderBookLevel> bids,
    List<OrderBookLevel> asks, {
    required int sequence,
  }) {
    final last = _sequence;
    if (!_valid || last == null || sequence <= last) {
      _valid = false;
      return false;
    }
    _put(_bids, bids);
    _put(_asks, asks);
    _sequence = sequence;
    return true;
  }

  /// The top [depth] of each side, or null while the book is not valid.
  OrderBookSnapshot? snapshot(Instrument instrument, {required DateTime at}) {
    if (!_valid) return null;
    return OrderBookSnapshot(
      instrument: instrument,
      bids: _top(_bids),
      asks: _top(_asks),
      at: at,
    );
  }

  static void _put(
    SplayTreeMap<Decimal, Decimal> side,
    List<OrderBookLevel> levels,
  ) {
    for (final level in levels) {
      if (level.qty == Decimal.zero) {
        side.remove(level.price);
      } else {
        side[level.price] = level.qty;
      }
    }
  }

  List<OrderBookLevel> _top(SplayTreeMap<Decimal, Decimal> side) => [
    for (final entry in side.entries.take(depth))
      OrderBookLevel(price: entry.key, qty: entry.value),
  ];
}
