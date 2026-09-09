import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// CoinGecko returns JSON numbers, so precision was already decided on
/// their side. We convert through the number's shortest string
/// representation, never through arithmetic on `double`.
Decimal decimalFromJsonNumber(Object? value, String field) {
  if (value is num) {
    final parsed = Decimal.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  throw FormatException('$field is not a number: $value');
}

/// `GET /simple/price?ids=..&vs_currencies=usd&include_24hr_change=true`:
/// `{ "bitcoin": { "usd": 77718, "usd_24h_change": -2.07 } }`.
///
/// Instruments whose id is missing from the payload are skipped: CoinGecko
/// silently drops unknown ids instead of failing the batch.
List<Quote> parseSimplePrice(
  Map<String, Object?> json,
  List<Instrument> instruments, {
  required DateTime at,
  String vsCurrency = 'usd',
}) {
  final quotes = <Quote>[];
  for (final instrument in instruments) {
    final entry = json[instrument.symbol];
    if (entry is! Map<String, Object?>) continue;
    final change = entry['${vsCurrency}_24h_change'];
    quotes.add(
      Quote(
        instrument: instrument,
        price: decimalFromJsonNumber(entry[vsCurrency], vsCurrency),
        change24hPct: change == null
            ? null
            : decimalFromJsonNumber(change, '${vsCurrency}_24h_change'),
        at: at,
      ),
    );
  }
  return quotes;
}

/// Candle width CoinGecko picks for `coins/{id}/ohlc?days=N`
/// (documented: 1–2 days → 30 min, 3–30 days → 4 h, 31+ days → 4 days).
Duration ohlcGranularity(int days) {
  if (days <= 2) return const Duration(minutes: 30);
  if (days <= 30) return const Duration(hours: 4);
  return const Duration(days: 4);
}

/// `[[timestamp, open, high, low, close], ...]`. The timestamp is the candle
/// close time; it is shifted back by [granularity] so the cache and the
/// chart see `openTime` like they do for Binance. No volume.
List<Candle> parseOhlc(List<Object?> rows, Duration granularity) {
  return [
    for (final row in rows)
      if (row is List<Object?> && row.length >= 5)
        Candle(
          openTime: _closeToOpen(row[0], granularity),
          open: decimalFromJsonNumber(row[1], 'open'),
          high: decimalFromJsonNumber(row[2], 'high'),
          low: decimalFromJsonNumber(row[3], 'low'),
          close: decimalFromJsonNumber(row[4], 'close'),
          volume: null,
        )
      else
        throw FormatException('ohlc row malformed: $row'),
  ];
}

DateTime _closeToOpen(Object? value, Duration granularity) {
  if (value is! num) throw FormatException('timestamp is not a number: $value');
  return DateTime.fromMillisecondsSinceEpoch(
    value.toInt(),
    isUtc: true,
  ).subtract(granularity);
}
