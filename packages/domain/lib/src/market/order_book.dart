import 'package:core/core.dart';
import 'package:domain/src/market/instrument.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_book.freezed.dart';

@freezed
abstract class OrderBookLevel with _$OrderBookLevel {
  const factory OrderBookLevel({required Decimal price, required Decimal qty}) =
      _OrderBookLevel;
}

/// Full top-N snapshot; the local state is replaced, never patched
/// (see ADR on `@depth10@100ms` vs diff streams).
@freezed
abstract class OrderBookSnapshot with _$OrderBookSnapshot {
  const factory OrderBookSnapshot({
    required Instrument instrument,

    /// Best bid first.
    required List<OrderBookLevel> bids,

    /// Best ask first.
    required List<OrderBookLevel> asks,
    required DateTime at,
  }) = _OrderBookSnapshot;
}
