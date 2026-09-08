import 'package:core/core.dart';
import 'package:domain/src/market/asset.dart';
import 'package:domain/src/market/candle.dart';
import 'package:domain/src/market/capabilities.dart';
import 'package:domain/src/market/instrument.dart';
import 'package:domain/src/market/interval.dart';
import 'package:domain/src/market/market_error.dart';
import 'package:domain/src/market/order_book.dart';
import 'package:domain/src/market/quote.dart';
import 'package:domain/src/market/trade.dart';

/// One interface, several implementations (Binance Global, Binance US,
/// CoinGecko). The feature layer never knows where a price came from.
abstract interface class MarketDataSource {
  /// Stable id: `binance`, `binance_us`, `coingecko`.
  String get id;

  /// Text for the `DataSourceBadge`, e.g. `Powered by CoinGecko`.
  String get attribution;

  Capabilities get capabilities;

  /// The source's instrument for [asset] quoted in [quote], or null when the
  /// source does not list that pair (Binance US has fewer pairs).
  Instrument? instrumentFor(Asset asset, String quote);

  /// Instruments for every asset the source supports, in catalog order.
  List<Instrument> instruments(List<Asset> assets, String quote);

  Future<Result<List<Quote>, MarketError>> quotes(List<Instrument> instruments);

  Future<Result<List<Candle>, MarketError>> klines(
    Instrument instrument,
    Interval interval, {
    int limit = 500,
  });

  Stream<Quote> quoteStream(List<Instrument> instruments);

  Stream<Candle> klineStream(Instrument instrument, Interval interval);

  /// Full top-10 snapshots; each event replaces the previous book.
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument);

  Stream<Trade> tradeStream(Instrument instrument);
}
