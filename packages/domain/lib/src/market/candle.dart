import 'package:core/core.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'candle.freezed.dart';

/// OHLCV candle. Keyed by [openTime]: a new candle with the same open time
/// replaces the previous one instead of being appended.
@freezed
abstract class Candle with _$Candle {
  const factory Candle({
    required DateTime openTime,
    required Decimal open,
    required Decimal high,
    required Decimal low,
    required Decimal close,

    /// Base-asset volume. Null for sources without volume (CoinGecko OHLC).
    required Decimal? volume,
  }) = _Candle;
}
