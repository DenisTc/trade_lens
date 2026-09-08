import 'package:domain/src/market/interval.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'capabilities.freezed.dart';

/// What a `MarketDataSource` can do. The UI hides the order book, the trade
/// tape and the interval selector when the active source lacks them.
@freezed
abstract class Capabilities with _$Capabilities {
  const factory Capabilities({
    required bool orderBook,
    required bool trades,
    required bool klineStream,
    required bool volume,
    required Set<Interval> intervals,
  }) = _Capabilities;

  /// Everything an exchange WebSocket API offers.
  static const full = Capabilities(
    orderBook: true,
    trades: true,
    klineStream: true,
    volume: true,
    intervals: {Interval.m1, Interval.m15, Interval.h1, Interval.d1},
  );

  /// Prices-only mode of the REST fallback.
  static const pricesOnly = Capabilities(
    orderBook: false,
    trades: false,
    klineStream: false,
    volume: false,
    intervals: {Interval.auto},
  );
}
