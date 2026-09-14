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
    this.backfillPageSize = 500,
    this.backfillMaxPages = 10,
  }) : _clock = clock ?? const Clock();

  /// Page size of the backfill after a reconnect, and how many pages it
  /// may walk back before giving up on a very long outage.
  final int backfillPageSize;
  final int backfillMaxPages;

  /// One book per symbol, shared by every listener and by the exchange
  /// subscription's lifetime: the snapshot comes once, on subscribe, and
  /// a listener that arrives while the subscription is still held gets
  /// the current book rather than a blank one.
  final Map<String, BybitOrderBook> _books = {};

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

  /// Live candles; after a reconnect the history since the last candle
  /// seen is paged in from the newest page backwards, while live candles
  /// are buffered. Then everything is emitted in order by open time, a
  /// live candle winning over history for the same open time, so a slow
  /// REST answer never rolls a newer close back. A reconnect during a
  /// backfill starts a new one and the older result is dropped.
  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) {
    final code = bybitIntervalCode(interval);
    final ws = _socket;
    late StreamController<Candle> controller;
    StreamSubscription<WsMessage>? frames;
    StreamSubscription<WsConnectionState>? states;
    DateTime? lastOpenTime;
    List<Candle>? buffered; // non-null while a backfill is running
    var reconnecting = false;
    var generation = 0;

    void emit(Candle candle) {
      lastOpenTime = candle.openTime;
      final pending = buffered;
      if (pending != null) {
        pending.add(candle);
      } else {
        controller.add(candle);
      }
    }

    Future<void> backfill() async {
      final since = lastOpenTime;
      if (since == null) return;
      final myGeneration = ++generation;
      buffered ??= [];
      _logger.info('backfilling ${instrument.symbol} $code from $since');
      final history = <DateTime, Candle>{};
      DateTime? before;
      for (var page = 0; page < backfillMaxPages; page++) {
        final result = await klines(
          instrument,
          interval,
          limit: backfillPageSize,
          before: before,
        );
        if (myGeneration != generation || controller.isClosed) return;
        final candles = switch (result) {
          Ok(:final value) => value,
          Err(:final error) => (() {
            controller.addError(error);
            return null;
          })(),
        };
        if (candles == null || candles.isEmpty) break;
        for (final c in candles) {
          if (!c.openTime.isBefore(since)) history[c.openTime] = c;
        }
        if (!candles.first.openTime.isAfter(since) ||
            candles.length < backfillPageSize) {
          break;
        }
        before = candles.first.openTime;
      }
      // Live updates win over history for the same openTime.
      for (final c in buffered ?? const <Candle>[]) {
        history[c.openTime] = c;
      }
      buffered = null;
      history.values.toList()
        ..sort((a, b) => a.openTime.compareTo(b.openTime))
        ..forEach(controller.add);
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
              emit(parseBybitKlineEvent(element));
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
        generation++;
        unawaited(frames?.cancel());
        unawaited(states?.cancel());
      },
    );
    return controller.stream;
  }

  /// A snapshot per frame, kept by the symbol's shared [BybitOrderBook].
  /// A frame out of sequence, or one that cannot be read, makes the book
  /// untrustworthy: the stream goes quiet and the topic is subscribed
  /// afresh so the exchange sends a new snapshot. A reconnect resends
  /// one on its own, and the book is invalidated in the meantime.
  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) {
    final ws = _socket;
    final topic = bybitBookTopic(instrument.symbol);
    final book = _books.putIfAbsent(instrument.symbol, BybitOrderBook.new);
    late StreamController<OrderBookSnapshot> controller;
    StreamSubscription<WsMessage>? frames;
    StreamSubscription<WsConnectionState>? states;

    void refresh(String why) {
      _logger.warn('book ${instrument.symbol}: $why, asking for a snapshot');
      book.invalidate();
      ws.resubscribe(topic);
    }

    void onFrame(WsMessage message) {
      try {
        final data = message.data['data'];
        if (data is! Map<String, Object?>) {
          throw FormatException('book data is not an object: $data');
        }
        final updateId = data['u'];
        if (updateId is! int) {
          throw FormatException('book u is not an int: $updateId');
        }
        final bids = parseBybitLevels(data['b'], 'b');
        final asks = parseBybitLevels(data['a'], 'a');
        // Bybit restarts a book with `u` = 1 and a full set of levels.
        if (message.data['type'] == 'snapshot' || updateId == 1) {
          book.applySnapshot(bids, asks, updateId: updateId);
        } else if (!book.applyDelta(bids, asks, updateId: updateId)) {
          refresh('frame out of sequence');
          return;
        }
        final snapshot = book.snapshot(
          instrument,
          at: _frameTime(message.data),
        );
        if (snapshot != null) controller.add(snapshot);
      } on FormatException catch (e) {
        refresh('unreadable frame');
        controller.addError(
          MarketError.parse(sourceId: id, message: e.message),
        );
      }
    }

    controller = StreamController<OrderBookSnapshot>(
      onListen: () {
        frames = ws
            .subscribe(topic)
            .listen(onFrame, onError: controller.addError);
        states = ws.states.listen((state) {
          if (state == WsConnectionState.reconnecting) book.invalidate();
        });
        // The subscription may already be held for another listener, or
        // still held from one that just left: then the snapshot is not
        // coming again, and the book as it stands is what there is.
        final current = book.snapshot(instrument, at: _clock.now().toUtc());
        if (current != null && ws.serverSubscriptions.contains(topic)) {
          controller.add(current);
        }
      },
      onCancel: () {
        unawaited(frames?.cancel());
        unawaited(states?.cancel());
      },
    );
    return controller.stream;
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
