import 'package:core/core.dart';
import 'package:data_market/src/binance/binance_hosts.dart';
import 'package:data_market/src/binance/binance_parsers.dart';
import 'package:data_market/src/binance/binance_request_queue.dart';
import 'package:data_market/src/binance/binance_rest_client.dart';
import 'package:data_market/src/errors.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

/// REST half of the Binance source. Streams are wired in with `ws_client`
/// (day 3); until then they throw so a missing wire-up fails loudly.
final class BinanceMarketDataSource implements MarketDataSource {
  BinanceMarketDataSource({
    required this._client,
    required this._hosts,
    this.defaultQuote = 'USDT',
    this._listedSymbols,
  });

  final BinanceRestClient _client;
  final BinanceHosts _hosts;

  /// Quote currency this deployment lists the catalog against.
  final String defaultQuote;

  /// When non-null only these symbols exist on the deployment
  /// (Binance.US lists fewer pairs). Null means "everything in the catalog".
  final Set<String>? _listedSymbols;

  @override
  String get id => _hosts.sourceId;

  @override
  String get attribution => 'Data: ${_hosts.label}';

  @override
  Capabilities get capabilities => Capabilities.full;

  @override
  Instrument? instrumentFor(Asset asset, String quote) {
    final symbol = '${asset.symbol}$quote'.toUpperCase();
    final listed = _listedSymbols;
    if (listed != null && !listed.contains(symbol)) return null;
    return Instrument(sourceId: id, symbol: symbol, base: asset, quote: quote);
  }

  @override
  List<Instrument> instruments(List<Asset> assets, String quote) => [
    for (final asset in assets) ?instrumentFor(asset, quote),
  ];

  @override
  Future<Result<List<Quote>, MarketError>> quotes(
    List<Instrument> instruments,
  ) async {
    if (instruments.isEmpty) return const Ok([]);
    final bySymbol = {for (final i in instruments) i.symbol: i};
    try {
      final rows = await _client.ticker24h(bySymbol.keys.toList());
      final quotes = <Quote>[];
      for (final row in rows) {
        final instrument = bySymbol[row['symbol']];
        if (instrument == null) continue;
        quotes.add(parseTicker24h(row, instrument));
      }
      return Ok(quotes);
    } on DioException catch (e) {
      return Err(marketErrorFromDio(id, e));
    } on BinanceRateLimitException catch (e) {
      return Err(
        MarketError.rateLimited(sourceId: id, retryAfter: e.retryAfter),
      );
    } on FormatException catch (e) {
      return Err(MarketError.parse(sourceId: id, message: e.message));
    }
  }

  @override
  Future<Result<List<Candle>, MarketError>> klines(
    Instrument instrument,
    Interval interval, {
    int limit = 500,
    DateTime? startTime,
  }) async {
    if (interval.duration == null) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Binance needs a fixed interval',
      );
    }
    try {
      final rows = await _client.klines(
        instrument.symbol,
        interval,
        limit: limit,
        startTime: startTime,
      );
      return Ok([for (final row in rows) parseKline(row)]);
    } on DioException catch (e) {
      return Err(marketErrorFromDio(id, e));
    } on BinanceRateLimitException catch (e) {
      return Err(
        MarketError.rateLimited(sourceId: id, retryAfter: e.retryAfter),
      );
    } on FormatException catch (e) {
      return Err(MarketError.parse(sourceId: id, message: e.message));
    }
  }

  @override
  Stream<Quote> quoteStream(List<Instrument> instruments) => _notWiredYet();

  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) =>
      _notWiredYet();

  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) =>
      _notWiredYet();

  @override
  Stream<Trade> tradeStream(Instrument instrument) => _notWiredYet();

  Never _notWiredYet() => throw UnimplementedError(
    'Binance streams are wired through ws_client (day 3 of the plan)',
  );
}
