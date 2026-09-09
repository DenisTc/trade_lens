import 'dart:async';

import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// In-memory source with a listener counter per instrument, standing in for
/// the WebSocket registry. Tests assert the counter, which is exactly what
/// the spec asks: "счётчик реестра уменьшается только после ухода
/// последнего потребителя".
final class FakeMarketDataSource implements MarketDataSource {
  FakeMarketDataSource({
    this.assets = defaultAssets,
    this.quote = 'USDT',
    this.capabilities = Capabilities.full,
    this.history = const [],
    this.klinesError,
  });

  final List<Asset> assets;
  final String quote;

  /// Returned by [klines] for every instrument and interval.
  final List<Candle> history;

  /// When set, [klines] fails with this error.
  final MarketError? klinesError;
  final Map<String, int> listeners = {};
  final Map<String, StreamController<Quote>> _controllers = {};
  final Map<String, StreamController<Candle>> _klines = {};
  final Map<String, StreamController<OrderBookSnapshot>> _books = {};
  final Map<String, StreamController<Trade>> _trades = {};
  final List<(Instrument, Interval)> klineRequests = [];

  @override
  String get id => 'fake';

  @override
  String get attribution => 'Data: Fake';

  @override
  final Capabilities capabilities;

  @override
  String get defaultQuote => quote;

  int listenerCount(Instrument instrument) => listeners[instrument.symbol] ?? 0;

  /// Push a price to everyone listening to [instrument].
  void emit(Instrument instrument, String price, {String? change}) {
    _controllers[instrument.symbol]?.add(
      Quote(
        instrument: instrument,
        price: Decimal.parse(price),
        change24hPct: change == null ? null : Decimal.parse(change),
        at: DateTime.utc(2026, 9, 8),
      ),
    );
  }

  @override
  Instrument instrumentFor(Asset asset, String quote) => Instrument(
    sourceId: id,
    symbol: '${asset.symbol}$quote',
    base: asset,
    quote: quote,
  );

  @override
  List<Instrument> instruments(List<Asset> assets, String quote) => [
    for (final asset in assets) instrumentFor(asset, quote),
  ];

  @override
  Future<Result<List<Quote>, MarketError>> quotes(
    List<Instrument> instruments,
  ) async => const Ok([]);

  @override
  Future<Result<List<Candle>, MarketError>> klines(
    Instrument instrument,
    Interval interval, {
    int limit = 500,
  }) async {
    klineRequests.add((instrument, interval));
    final error = klinesError;
    return error == null ? Ok(history) : Err(error);
  }

  void emitCandle(Instrument instrument, Candle candle) =>
      _klines[instrument.symbol]?.add(candle);

  void emitBook(Instrument instrument, OrderBookSnapshot book) =>
      _books[instrument.symbol]?.add(book);

  void emitTrade(Instrument instrument, Trade trade) =>
      _trades[instrument.symbol]?.add(trade);

  @override
  Stream<Quote> quoteStream(List<Instrument> instruments) {
    final instrument = instruments.single;
    final controller = _controllers.putIfAbsent(
      instrument.symbol,
      StreamController<Quote>.broadcast,
    );
    late StreamController<Quote> out;
    StreamSubscription<Quote>? inner;
    out = StreamController<Quote>(
      onListen: () {
        listeners[instrument.symbol] = listenerCount(instrument) + 1;
        inner = controller.stream.listen(out.add);
      },
      onCancel: () {
        listeners[instrument.symbol] = listenerCount(instrument) - 1;
        unawaited(inner?.cancel());
      },
    );
    return out.stream;
  }

  @override
  Stream<Candle> klineStream(Instrument instrument, Interval interval) =>
      _klines
          .putIfAbsent(instrument.symbol, StreamController<Candle>.broadcast)
          .stream;

  @override
  Stream<OrderBookSnapshot> orderBookStream(Instrument instrument) => _books
      .putIfAbsent(
        instrument.symbol,
        StreamController<OrderBookSnapshot>.broadcast,
      )
      .stream;

  @override
  Stream<Trade> tradeStream(Instrument instrument) => _trades
      .putIfAbsent(instrument.symbol, StreamController<Trade>.broadcast)
      .stream;
}
