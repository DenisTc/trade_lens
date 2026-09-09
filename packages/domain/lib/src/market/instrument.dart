import 'package:domain/src/market/asset.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'instrument.freezed.dart';

/// A tradable pair on a specific source, e.g. `BTCUSDT` on `binance`.
///
/// Value equality matters: instruments are keys of family providers and of
/// the candle cache (`sourceId + symbol + interval`).
@freezed
abstract class Instrument with _$Instrument {
  const factory Instrument({
    /// Id of the `MarketDataSource` that understands [symbol].
    required String sourceId,

    /// Source-specific symbol: `BTCUSDT` for Binance, `bitcoin` for CoinGecko.
    required String symbol,
    required Asset base,

    /// Quote currency as the user sees it: `USDT`, `USD`.
    required String quote,
  }) = _Instrument;

  const Instrument._();

  /// `BTC/USDT`, independent of the source's own symbol format.
  String get displayName => '${base.symbol}/$quote';
}
