import 'dart:async';

import 'package:clock/clock.dart';
import 'package:core/core.dart';
import 'package:data_market/src/bybit/bybit_hosts.dart';
import 'package:data_market/src/bybit/bybit_order_book.dart';
import 'package:data_market/src/bybit/bybit_parsers.dart';
import 'package:data_market/src/bybit/bybit_rest_client.dart';
import 'package:data_market/src/bybit/bybit_ws_protocol.dart';
import 'package:data_market/src/errors.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:ws_client/ws_client.dart';

/// Bybit spot over REST (history, batch quotes) and one [WsClient] on
/// [BybitWsProtocol] (live quotes, candles, the book, trades).
///
/// The second exchange behind the same interface. What differed from
/// Binance is exactly what the feature layer never sees: the wire format
/// of the socket, a book that arrives as deltas, klines listed newest
/// first, a 24h change given as a fraction.
final class BybitMarketDataSource implements MarketDataSource {
  BybitMarketDataSource({
    required this._client,
    this._ws,
    this._logger = const NoopLogger(),
    Clock? clock,
    this.backfillLimit = 500,
  }) : _clock = clock ?? const Clock();

  /// Candles fetched after a reconnect, from the last one seen.
  final int backfillLimit;

  final BybitRestClient _client;
  final WsClient? _ws;
  final Logger _logger;
  final Clock _clock;

  @override
  String get id => BybitHosts.sourceId;

  @override
  String get attribution => 'Data: ${BybitHosts.label}';

  @override
  Capabilities get capabilities => Capabilities.full;

  @override
  String get defaultQuote => 'USDT';

  @override
  Instrument? instrumentFor(Asset asset, String quote) => Instrument(
    sourceId: id,
    symbol: '${asset.symbol}$quote'.toUpperCase(),
    base: asset,
    quote: quote,
  );

  @override
  List<Instrument> instruments(List<Asset> assets, String quote) => [
    for (final asset in assets) ?instrumentFor(asset, quote),
  ];

  // ------------------------------------------------------------------ REST

  @override
  Future<Result<List<Quote>, MarketError>> quotes(
    List<Instrument> instruments,
  ) {
    if (instruments.isEmpty) return Future.value(const Ok([]));
    final bySymbol = {for (final i in instruments) i.symbol: i};
    return _guard(() async {
      final at = _clock.now().toUtc();
      final quotes = <Quote>[];
      for (final row in await _client.tickers()) {
        if (row is! Map<String, Object?>) {
          throw FormatException('ticker element is not an object: $row');
        }
        final instrument = bySymbol[row['symbol']];
        if (instrument == null) continue;
        quotes.add(parseBybitTicker(row, instrument, at: at));
      }
      return quotes;
    });
  }

  @override
  Future<Result<List<Candle>, MarketError>> klines(
    Instrument instrument,
    Interval interval, {
    int limit = 500,
    DateTime? before,
  }) {
    final code = bybitIntervalCode(interval);
    return _guard(() async {
      final rows = await _client.kline(
        instrument.symbol,
        code,
        limit: limit,
        // `end` is inclusive of a candle opening at that instant.
        end: before?.subtract(const Duration(milliseconds: 1)),
      );
      // Newest first on the wire; oldest first everywhere in the app.
      return [for (final row in rows.reversed) parseBybitKlineRow(row)];
    });
  }

  Future<Result<T, MarketError>> _guard<T>(Future<T> Function() call) async {
    try {
      return Ok(await call());
    } on DioException catch (e) {
      return Err(marketErrorFromDio(id, e));
    } on BybitApiException catch (e) {
      // 10006 is Bybit's rate limit; every other code is the request.
      return Err(
        e.code == 10006
            ? MarketError.rateLimited(
                sourceId: id,
                retryAfter: const Duration(seconds: 60),
              )
            : MarketError.unavailable(sourceId: id, reason: '$e'),
      );
    } on FormatException catch (e) {
      return Err(MarketError.parse(sourceId: id, message: e.message));
    }
  }

  // --------------------------------------------------------------- streams

  WsClient get _socket =>
      _ws ??
      (throw StateError('BybitMarketDataSource was built without a WsClient'));

  @override
  Stream<Quote> quoteStream(List<Instrument> instruments) {
    final ws = _socket;
    return _merge([
      for (final instrument in instruments)
        _mapFrames(
          ws.subscribe(bybitTickerTopic(instrument.symbol)),
          (frame) => parseBybitTicker(
            frame['data'],
            instrument,
            at: _frameTime(frame),
          ),
        ),
    ]);
  }

  /// Live candles; after a reconnect one page of history from the last
  /// candle seen is merged in, live updates winning on the same open
  /// time. One page: a socket outage longer than [backfillLimit] candles
  /// of the interval is what the history paging on the chart is for.
  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) {
    final code = bybitIntervalCode(interval);
    final ws = _socket;
    late StreamController<Candle> controller;
    StreamSubscription<WsMessage>? frames;
    StreamSubscription<WsConnectionState>? states;
    DateTime? lastOpenTime;
    var reconnecting = false;

    Future<void> backfill() async {
      final since = lastOpenTime;
      if (since == null) return;
      _logger.info('backfilling ${instrument.symbol} $code from $since');
      final result = await klines(instrument, interval, limit: backfillLimit);
      if (controller.isClosed) return;
      switch (result) {
        case Ok(:final value):
          for (final c in value) {
            if (!c.openTime.isBefore(since)) controller.add(c);
          }
        case Err(:final error):
          controller.addError(error);
      }
    }

    controller = StreamController<Candle>(
      onListen: () {
        frames = ws.subscribe(bybitKlineTopic(instrument.symbol, code)).listen((
          message,
        ) {
          final list = message.data['data'];
          if (list is! List<Object?>) return;
          try {
            for (final element in list) {
              final candle = parseBybitKlineEvent(element);
              lastOpenTime = candle.openTime;
              controller.add(candle);
            }
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

  /// A snapshot per frame, kept by [BybitOrderBook] from the deltas. A
  /// frame out of sequence yields nothing until the next snapshot, and
  /// a reconnect starts a fresh book, since Bybit resends the snapshot.
  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) {
    final book = BybitOrderBook();
    return _socket
        .subscribe(bybitBookTopic(instrument.symbol))
        .map((message) {
          try {
            final data = message.data['data'];
            if (data is! Map<String, Object?>) {
              throw FormatException('book data is not an object: $data');
            }
            final sequence = data['seq'];
            if (sequence is! int) {
              throw FormatException('book seq is not an int: $sequence');
            }
            final bids = parseBybitLevels(data['b'], 'b');
            final asks = parseBybitLevels(data['a'], 'a');
            if (message.data['type'] == 'snapshot') {
              book.applySnapshot(bids, asks, sequence: sequence);
            } else if (!book.applyDelta(bids, asks, sequence: sequence)) {
              _logger.warn('book ${instrument.symbol}: frame out of sequence');
              return null;
            }
            return book.snapshot(instrument, at: _frameTime(message.data));
          } on FormatException catch (e) {
            throw MarketError.parse(sourceId: id, message: e.message);
          }
        })
        .where((snapshot) => snapshot != null)
        .cast<OrderBookSnapshot>();
  }

  @override
  Stream<Trade> tradeStream(Instrument instrument) =>
      _socket.subscribe(bybitTradeTopic(instrument.symbol)).expand((message) {
        final list = message.data['data'];
        if (list is! List<Object?>) return const <Trade>[];
        try {
          return [for (final e in list) parseBybitTrade(e, instrument)];
        } on FormatException catch (e) {
          throw MarketError.parse(sourceId: id, message: e.message);
        }
      });

  DateTime _frameTime(Map<String, Object?> frame) {
    final ts = frame['ts'];
    return ts is int
        ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true)
        : _clock.now().toUtc();
  }

  Stream<T> _mapFrames<T>(
    Stream<WsMessage> frames,
    T Function(Map<String, Object?> frame) parse,
  ) => frames.map((message) {
    try {
      return parse(message.data);
    } on FormatException catch (e) {
      throw MarketError.parse(sourceId: id, message: e.message);
    }
  });

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
