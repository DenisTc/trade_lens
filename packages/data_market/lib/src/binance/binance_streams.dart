import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// Stream names of the combined WebSocket endpoint. Binance requires
/// lowercase symbols here, unlike REST.
String miniTickerStreamName(String symbol) =>
    '${symbol.toLowerCase()}@miniTicker';

String klineStreamName(String symbol, Interval interval) =>
    '${symbol.toLowerCase()}@kline_${interval.code}';

/// Partial book: the full top-10 every 100 ms. Replaces the local book;
/// no diff bookkeeping (ADR-0002).
String depth10StreamName(String symbol) =>
    '${symbol.toLowerCase()}@depth10@100ms';

String tradeStreamName(String symbol) => '${symbol.toLowerCase()}@trade';

/// `@miniTicker` payload: `{c: close, o: open, h, l, v, q, E}`. There is no
/// percent field, so the 24h change is derived from close and open.
Quote parseMiniTicker(Map<String, Object?> data, Instrument instrument) {
  final close = _decimal(data['c'], 'c');
  final open = _decimal(data['o'], 'o');
  return Quote(
    instrument: instrument,
    price: close,
    change24hPct: open == Decimal.zero
        ? null
        : ((close - open) * Decimal.fromInt(100) / open).toDecimal(
            scaleOnInfinitePrecision: 3,
          ),
    at: _millis(data['E'], 'E'),
  );
}

/// `@depth10@100ms` payload: `{lastUpdateId, bids: [[p, q]…], asks: […]}`.
/// The partial-book stream carries no timestamp; [at] is the receive time.
OrderBookSnapshot parseDepth10(
  Map<String, Object?> data,
  Instrument instrument, {
  required DateTime at,
}) {
  return OrderBookSnapshot(
    instrument: instrument,
    bids: _levels(data['bids'], 'bids'),
    asks: _levels(data['asks'], 'asks'),
    at: at,
  );
}

/// `@trade` payload: `{t: id, p, q, T: time, m: isBuyerMaker}`.
Trade parseTradeEvent(Map<String, Object?> data, Instrument instrument) {
  final id = data['t'];
  final isBuyerMaker = data['m'];
  if (id is! int || isBuyerMaker is! bool) {
    throw FormatException('trade event malformed: $data');
  }
  return Trade(
    instrument: instrument,
    id: '$id',
    price: _decimal(data['p'], 'p'),
    qty: _decimal(data['q'], 'q'),
    at: _millis(data['T'], 'T'),
    isBuyerMaker: isBuyerMaker,
  );
}

List<OrderBookLevel> _levels(Object? raw, String field) {
  if (raw is! List<Object?>) throw FormatException('$field is not a list');
  return [
    for (final level in raw)
      if (level is List<Object?> && level.length >= 2)
        OrderBookLevel(
          price: _decimal(level[0], '$field.price'),
          qty: _decimal(level[1], '$field.qty'),
        )
      else
        throw FormatException('$field level malformed: $level'),
  ];
}

Decimal _decimal(Object? value, String field) {
  if (value is String) {
    final parsed = Decimal.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$field is not a decimal string: $value');
}

DateTime _millis(Object? value, String field) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  throw FormatException('$field is not epoch millis: $value');
}
