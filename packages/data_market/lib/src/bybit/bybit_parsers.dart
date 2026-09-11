import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// Pure parsers for Bybit payloads. Prices are decimal strings on the
/// wire and stay decimal here; nothing goes through `double`.

/// Bybit's kline interval codes: minutes as numbers, days as `D`.
String bybitIntervalCode(Interval interval) => switch (interval) {
  Interval.m1 => '1',
  Interval.m15 => '15',
  Interval.h1 => '60',
  Interval.d1 => 'D',
  Interval.auto => throw ArgumentError.value(
    interval,
    'interval',
    'Bybit needs a fixed interval',
  ),
};

/// `market/kline` row: `[start, open, high, low, close, volume, turnover]`,
/// every field a string. Rows arrive newest first; the caller reverses.
Candle parseBybitKlineRow(Object? element) {
  if (element is! List<Object?>) {
    throw FormatException('kline row is not an array: $element');
  }
  if (element.length < 6) {
    throw FormatException('kline row too short: ${element.length}');
  }
  return Candle(
    openTime: _millisString(element[0], 'start'),
    open: _decimal(element[1], 'open'),
    high: _decimal(element[2], 'high'),
    low: _decimal(element[3], 'low'),
    close: _decimal(element[4], 'close'),
    volume: _decimal(element[5], 'volume'),
  );
}

/// `kline.<interval>.<symbol>` frame element: `{start, open, high, low,
/// close, volume, confirm, ...}` with `start` as a number this time.
Candle parseBybitKlineEvent(Object? element) {
  final k = _object(element, 'kline');
  return Candle(
    openTime: _millis(k['start'], 'start'),
    open: _decimal(k['open'], 'open'),
    high: _decimal(k['high'], 'high'),
    low: _decimal(k['low'], 'low'),
    close: _decimal(k['close'], 'close'),
    volume: _decimal(k['volume'], 'volume'),
  );
}

/// A ticker, from REST (`market/tickers` element) or the stream
/// (`tickers.<symbol>` data): `lastPrice` and `price24hPcnt`, the latter
/// a fraction (`-0.0152`), which the domain wants in percent. [at] is
/// the frame's timestamp; REST carries none per element.
Quote parseBybitTicker(
  Object? element,
  Instrument instrument, {
  required DateTime at,
}) {
  final json = _object(element, 'ticker');
  final fraction = json['price24hPcnt'];
  return Quote(
    instrument: instrument,
    price: _decimal(json['lastPrice'], 'lastPrice'),
    change24hPct: fraction is String && Decimal.tryParse(fraction) != null
        ? Decimal.parse(fraction) * Decimal.fromInt(100)
        : null,
    at: at,
  );
}

/// `publicTrade.<symbol>` element: `{i: id, T: time, p, v, S: Buy|Sell}`.
/// `S` is the taker's side, so the maker is the buyer when it says Sell.
Trade parseBybitTrade(Object? element, Instrument instrument) {
  final json = _object(element, 'trade');
  final id = json['i'];
  final side = json['S'];
  if (id is! String || (side != 'Buy' && side != 'Sell')) {
    throw FormatException('trade malformed: $json');
  }
  return Trade(
    instrument: instrument,
    id: id,
    price: _decimal(json['p'], 'p'),
    qty: _decimal(json['v'], 'v'),
    at: _millis(json['T'], 'T'),
    isBuyerMaker: side == 'Sell',
  );
}

/// Price and size pairs of a book frame, `[["76822.3", "0.04"], ...]`.
List<OrderBookLevel> parseBybitLevels(Object? raw, String field) {
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

Map<String, Object?> _object(Object? value, String what) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$what is not an object: $value');
  }
  return value;
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

DateTime _millisString(Object? value, String field) {
  final parsed = value is String ? int.tryParse(value) : null;
  if (parsed == null) {
    throw FormatException('$field is not epoch millis in a string: $value');
  }
  return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
}
