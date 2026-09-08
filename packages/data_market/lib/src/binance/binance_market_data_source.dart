import 'dart:async';

import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:data_market/src/binance/binance_hosts.dart';
import 'package:data_market/src/binance/binance_parsers.dart';
import 'package:data_market/src/binance/binance_request_queue.dart';
import 'package:data_market/src/binance/binance_rest_client.dart';
import 'package:data_market/src/binance/binance_streams.dart';
import 'package:data_market/src/errors.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:ws_client/ws_client.dart';

/// Binance over REST (history, batch quotes) and one shared [WsClient]
/// (live quotes, candles, top-10 book, trades). Works for Global, the
/// market-data host and Binance.US alike; only [BinanceHosts] differ.
final class BinanceMarketDataSource implements MarketDataSource {
  BinanceMarketDataSource({
    required this._client,
    required this._hosts,
    this._ws,
    this.defaultQuote = 'USDT',
    this._listedSymbols,
    this._logger = const NoopLogger(),
    Clock? clock,
  }) : _clock = clock ?? const Clock();

  final BinanceRestClient _client;
  final BinanceHosts _hosts;
  final WsClient? _ws;
  final Logger _logger;
  final Clock _clock;

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

  // ------------------------------------------------------------------ REST

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
        if (row is! Map<String, Object?>) {
          throw FormatException('ticker element is not an object: $row');
        }
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

  // --------------------------------------------------------------- streams

  WsClient get _socket =>
      _ws ??
      (throw StateError(
        'BinanceMarketDataSource($id) was built without a WsClient',
      ));

  /// One miniTicker subscription per instrument, merged. The registry in
  /// `ws_client` dedupes symbols shared with other screens.
  @override
  Stream<Quote> quoteStream(List<Instrument> instruments) {
    final ws = _socket;
    return _merge([
      for (final instrument in instruments)
        _mapFrames(
          ws.subscribe(miniTickerStreamName(instrument.symbol)),
          (data) => parseMiniTicker(data, instrument),
        ),
    ]);
  }

  /// Live candles plus a REST backfill after every reconnect, from the last
  /// candle we saw. A candle with an already-seen `openTime` is an update,
  /// which is how the chart treats it.
  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) {
    if (interval.duration == null) {
      throw ArgumentError.value(interval, 'interval', 'fixed interval only');
    }
    final ws = _socket;
    late StreamController<Candle> controller;
    StreamSubscription<WsMessage>? frames;
    StreamSubscription<WsConnectionState>? states;
    DateTime? lastOpenTime;
    var reconnecting = false;

    Future<void> backfill() async {
      final since = lastOpenTime;
      if (since == null) return;
      _logger.info(
        'backfilling ${instrument.symbol} ${interval.code} from $since',
      );
      final result = await klines(instrument, interval, startTime: since);
      if (controller.isClosed) return;
      result.when(
        ok: (candles) => candles.forEach(controller.add),
        err: controller.addError,
      );
    }

    controller = StreamController<Candle>(
      onListen: () {
        frames = ws
            .subscribe(klineStreamName(instrument.symbol, interval))
            .listen((message) {
              final k = message.data['k'];
              if (k is! Map<String, Object?>) return;
              try {
                final candle = parseKlineEvent(k);
                lastOpenTime = candle.openTime;
                controller.add(candle);
              } on FormatException catch (e) {
                controller.addError(
                  MarketError.parse(sourceId: id, message: e.message),
                );
              }
            }, onError: controller.addError);
        states = ws.states.listen((state) {
          if (state == WsConnectionState.reconnecting) reconnecting = true;
          if (state == WsConnectionState.connected && reconnecting) {
            reconnecting = false;
            unawaited(backfill());
          }
        });
      },
      onCancel: () {
        unawaited(frames?.cancel());
        unawaited(states?.cancel());
      },
    );
    return controller.stream;
  }

  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) =>
      _mapFrames(
        _socket.subscribe(depth10StreamName(instrument.symbol)),
        (data) => parseDepth10(data, instrument, at: _clock.now().toUtc()),
      );

  @override
  Stream<Trade> tradeStream(Instrument instrument) => _mapFrames(
    _socket.subscribe(tradeStreamName(instrument.symbol)),
    (data) => parseTradeEvent(data, instrument),
  );

  Stream<T> _mapFrames<T>(
    Stream<WsMessage> frames,
    T Function(Map<String, Object?> data) parse,
  ) {
    return frames.map((message) {
      try {
        return parse(message.data);
      } on FormatException catch (e) {
        throw MarketError.parse(sourceId: id, message: e.message);
      }
    });
  }

  /// Merges single-subscription streams; cancelling the result cancels all.
  Stream<T> _merge<T>(List<Stream<T>> sources) {
    if (sources.length == 1) return sources.single;
    late StreamController<T> controller;
    final subscriptions = <StreamSubscription<T>>[];
    controller = StreamController<T>(
      onListen: () {
        for (final source in sources) {
          subscriptions.add(
            source.listen(controller.add, onError: controller.addError),
          );
        }
      },
      onPause: () {
        for (final s in subscriptions) {
          s.pause();
        }
      },
      onResume: () {
        for (final s in subscriptions) {
          s.resume();
        }
      },
      onCancel: () {
        for (final s in subscriptions) {
          unawaited(s.cancel());
        }
      },
    );
    return controller.stream;
  }
}
