import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// Pure parsers for Binance REST payloads. Prices arrive as strings and
/// are parsed straight into [Decimal]; nothing goes through `double`.

/// `GET /api/v3/ticker/24hr` element.
Quote parseTicker24h(Map<String, Object?> json, Instrument instrument) {
  return Quote(
    instrument: instrument,
    price: _decimal(json['lastPrice'], 'lastPrice'),
    change24hPct: _decimal(json['priceChangePercent'], 'priceChangePercent'),
    at: _millis(json['closeTime'], 'closeTime'),
  );
}

/// `GET /api/v3/klines` row:
/// `[openTime, open, high, low, close, volume, closeTime, ...]`.
Candle parseKline(List<Object?> row) {
  if (row.length < 6) {
    throw FormatException('kline row too short: ${row.length}');
  }
  return Candle(
    openTime: _millis(row[0], 'openTime'),
    open: _decimal(row[1], 'open'),
    high: _decimal(row[2], 'high'),
    low: _decimal(row[3], 'low'),
    close: _decimal(row[4], 'close'),
    volume: _decimal(row[5], 'volume'),
  );
}

/// `@kline_<interval>` stream payload (`k` object).
Candle parseKlineEvent(Map<String, Object?> k) {
  return Candle(
    openTime: _millis(k['t'], 't'),
    open: _decimal(k['o'], 'o'),
    high: _decimal(k['h'], 'h'),
    low: _decimal(k['l'], 'l'),
    close: _decimal(k['c'], 'c'),
    volume: _decimal(k['v'], 'v'),
  );
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
