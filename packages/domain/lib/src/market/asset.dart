import 'package:freezed_annotation/freezed_annotation.dart';

part 'asset.freezed.dart';

/// A crypto asset independent of any data source.
///
/// CoinGecko `bitcoin/usd` and Binance `BTCUSDT` are two `Instrument`s of the
/// same `Asset`; the portfolio stores assets, sources map them to instruments.
@freezed
abstract class Asset with _$Asset {
  const factory Asset({
    /// Stable lowercase id used as a key everywhere, e.g. `btc`.
    required String id,

    /// Ticker symbol as shown to the user, e.g. `BTC`.
    required String symbol,

    /// Human name, e.g. `Bitcoin`.
    required String name,
  }) = _Asset;
}
