import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:meta/meta.dart';

/// The two tools the model may call. Data comes from what the app already
/// holds (providers, cache), never from a fresh network call, and the
/// arguments are validated against allowlists before anything runs.
abstract interface class MarketTools {
  /// Instruments the model may ask about; in the app this is the single
  /// pair the user opened the summary for, because that is what the
  /// consent covers. `symbol` in a call is matched case-insensitively.
  List<Instrument> get instruments;

  /// Attribution of the active source ("Binance"), handed to the model so
  /// it states where the numbers came from instead of guessing.
  String get sourceName;

  /// Intervals the active source offers.
  Set<Interval> get intervals;

  /// Up to [limit] most recent candles, oldest first.
  Future<List<Candle>> klines(
    Instrument instrument,
    Interval interval,
    int limit,
  );

  /// The latest snapshot, or null when the source has no order book.
  Future<OrderBookSnapshot?> orderBook(Instrument instrument);
}

/// A tool call as parsed from the stream: name and JSON input.
@immutable
final class ToolCall {
  const ToolCall({required this.id, required this.name, required this.input});

  final String id;
  final String name;
  final Map<String, Object?> input;
}

/// Definitions sent to the API. `strict` keeps the input on-schema.
abstract final class ToolSchemas {
  static const getKlines = 'get_klines';
  static const getOrderBook = 'get_orderbook';
  static const maxKlines = 200;

  static List<Map<String, Object?>> definitions({
    required Iterable<String> symbols,
    required Iterable<String> intervals,
  }) => [
    {
      'name': getKlines,
      'description':
          'Recent candles (open, high, low, close, volume) of an instrument '
          'from the data already loaded in the app. Oldest first. limit is '
          'the number of candles, between 5 and $maxKlines; values outside '
          'that range are clamped.',
      'strict': true,
      'input_schema': {
        'type': 'object',
        'properties': {
          'instrument': {'type': 'string', 'enum': symbols.toList()},
          'interval': {'type': 'string', 'enum': intervals.toList()},
          'limit': {'type': 'integer'},
        },
        'required': ['instrument', 'interval', 'limit'],
        'additionalProperties': false,
      },
    },
    {
      'name': getOrderBook,
      'description':
          'Top of the order book (best bids and asks with quantities) of an '
          'instrument, or "unavailable" when the source has no book.',
      'strict': true,
      'input_schema': {
        'type': 'object',
        'properties': {
          'instrument': {'type': 'string', 'enum': symbols.toList()},
        },
        'required': ['instrument'],
        'additionalProperties': false,
      },
    },
  ];
}

/// Runs a validated tool call and renders the result as compact text for
/// the model. Anything off the allowlist returns an error result instead
/// of throwing, so the model can recover.
final class ToolRunner {
  const ToolRunner(this.tools);

  final MarketTools tools;

  Future<String> run(ToolCall call) async {
    final instrument = _instrument(call.input['instrument']);
    if (instrument == null) return 'error: unknown instrument';
    switch (call.name) {
      case ToolSchemas.getKlines:
        final interval = _interval(call.input['interval']);
        if (interval == null) return 'error: unknown interval';
        final raw = call.input['limit'];
        final limit = raw is int ? raw.clamp(5, ToolSchemas.maxKlines) : 50;
        final candles = await tools.klines(instrument, interval, limit);
        if (candles.isEmpty) return 'unavailable: not loaded in the app';
        return 'source=${tools.sourceName}\n'
            '${renderKlines(candles, interval)}';
      case ToolSchemas.getOrderBook:
        final book = await tools.orderBook(instrument);
        if (book == null) return 'unavailable';
        return 'source=${tools.sourceName}\n${renderOrderBook(book)}';
      default:
        return 'error: unknown tool';
    }
  }

  Instrument? _instrument(Object? raw) {
    if (raw is! String) return null;
    final symbol = raw.toUpperCase();
    for (final i in tools.instruments) {
      if (i.symbol.toUpperCase() == symbol) return i;
    }
    return null;
  }

  Interval? _interval(Object? raw) {
    if (raw is! String) return null;
    for (final i in tools.intervals) {
      if (i.code == raw) return i;
    }
    return null;
  }

  /// One line per candle: `time open high low close volume`. Compact CSV
  /// keeps the token count low (~12 tokens per candle).
  static String renderKlines(List<Candle> candles, Interval interval) {
    final b = StringBuffer(
      'interval=${interval.code} time,open,high,low,close,volume (UTC)\n',
    );
    for (final c in candles) {
      b
        ..write(c.openTime.toUtc().toIso8601String().substring(0, 16))
        ..write(',')
        ..write(c.open)
        ..write(',')
        ..write(c.high)
        ..write(',')
        ..write(c.low)
        ..write(',')
        ..write(c.close)
        ..write(',')
        ..write(c.volume ?? '-')
        ..write('\n');
    }
    return b.toString();
  }

  static String renderOrderBook(OrderBookSnapshot book) {
    String side(List<OrderBookLevel> levels) =>
        levels.map((l) => '${l.price}x${l.qty}').join(' ');
    final bidQty = book.bids.fold(Decimal.zero, (a, l) => a + l.qty);
    final askQty = book.asks.fold(Decimal.zero, (a, l) => a + l.qty);
    return 'as of ${book.at.toUtc().toIso8601String().substring(0, 19)}Z\n'
        'bids (price x qty, best first): ${side(book.bids)}\n'
        'asks (price x qty, best first): ${side(book.asks)}\n'
        'total bid qty $bidQty, total ask qty $askQty';
  }
}
