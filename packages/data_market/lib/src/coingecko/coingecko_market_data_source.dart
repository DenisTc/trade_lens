import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:data_market/src/coingecko/coingecko_ids.dart';
import 'package:data_market/src/coingecko/coingecko_parsers.dart';
import 'package:data_market/src/coingecko/coingecko_rest_client.dart';
import 'package:data_market/src/coingecko/quote_poller.dart';
import 'package:data_market/src/errors.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

/// REST-only fallback: prices and 24h change for the whole catalog in one
/// request, OHLC with CoinGecko's own granularity, no book, no tape,
/// no volume. Polls every [pollInterval] while listened to; the app stops
/// listening in background (spec, "Режим «только цены»").
final class CoinGeckoMarketDataSource implements MarketDataSource {
  CoinGeckoMarketDataSource({
    required this.client,
    this.vsCurrency = 'usd',
    this.pollInterval = const Duration(seconds: 60),
    Clock? clock,
  }) : _clock = clock ?? const Clock() {
    _poller = QuotePoller(fetch: quotes, interval: pollInterval);
  }

  static const sourceId = 'coingecko';

  final CoinGeckoRestClient client;
  final String vsCurrency;
  final Duration pollInterval;
  final Clock _clock;
  late final QuotePoller _poller;

  @override
  String get id => sourceId;

  /// Wording from CoinGecko's attribution guide.
  @override
  String get attribution => 'Powered by CoinGecko';

  @override
  Capabilities get capabilities => Capabilities.pricesOnly;

  @override
  String get defaultQuote => vsCurrency.toUpperCase();

  @override
  Instrument? instrumentFor(Asset asset, String quote) {
    final geckoId = coinGeckoIdFor(asset);
    if (geckoId == null || quote.toLowerCase() != vsCurrency) return null;
    return Instrument(
      sourceId: id,
      symbol: geckoId,
      base: asset,
      quote: quote.toUpperCase(),
    );
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
    try {
      final json = await client.simplePrice([
        for (final i in instruments) i.symbol,
      ], vsCurrency: vsCurrency);
      return Ok(
        parseSimplePrice(
          json,
          instruments,
          at: _clock.now().toUtc(),
          vsCurrency: vsCurrency,
        ),
      );
    } on DioException catch (e) {
      return Err(_error(e));
    } on FormatException catch (e) {
      return Err(MarketError.parse(sourceId: id, message: e.message));
    }
  }

  /// Days requested per interval; CoinGecko then picks the candle width
  /// (see [ohlcGranularity]). `auto` means "one day of 30-minute candles".
  static int daysFor(Interval interval) => switch (interval) {
    Interval.auto || Interval.m1 || Interval.m15 => 1,
    Interval.h1 => 7,
    Interval.d1 => 90,
  };

  @override
  Future<Result<List<Candle>, MarketError>> klines(
    Instrument instrument,
    Interval interval, {
    int limit = 500,
    DateTime? before,
  }) async {
    // One OHLC window per call is all CoinGecko offers; `before` has
    // nothing to page into and Capabilities.history says so.
    final days = daysFor(interval);
    try {
      final rows = await client.ohlc(
        instrument.symbol,
        days: days,
        vsCurrency: vsCurrency,
      );
      final candles = parseOhlc(rows, ohlcGranularity(days));
      return Ok(
        candles.length <= limit
            ? candles
            : candles.sublist(candles.length - limit),
      );
    } on DioException catch (e) {
      return Err(_error(e));
    } on FormatException catch (e) {
      return Err(MarketError.parse(sourceId: id, message: e.message));
    }
  }

  /// Quotes for [instruments], served by one shared polling loop: the first
  /// listener triggers a request, then one batch request every
  /// [pollInterval] for the union of everything listened to. Errors are
  /// forwarded as [MarketError] events, the stream stays open.
  @override
  Stream<Quote> quoteStream(List<Instrument> instruments) =>
      _poller.streamFor(instruments);

  /// Instruments currently polled (diagnostics, tests).
  Set<Instrument> get polledInstruments => _poller.wanted;

  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) =>
      const Stream.empty();

  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) =>
      const Stream.empty();

  @override
  Stream<Trade> tradeStream(Instrument instrument) => const Stream.empty();

  /// 429 on the shared demo key means the monthly or per-minute quota is
  /// gone; the UI shows "Резервный источник исчерпал лимит", not a spinner.
  MarketError _error(DioException e) => e.response?.statusCode == 429
      ? MarketError.quotaExhausted(sourceId: id)
      : marketErrorFromDio(id, e);
}
