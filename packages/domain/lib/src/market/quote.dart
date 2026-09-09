import 'package:core/core.dart';
import 'package:domain/src/market/instrument.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'quote.freezed.dart';

/// Last price of an instrument with the 24h change, when the source has it.
@freezed
abstract class Quote with _$Quote {
  const factory Quote({
    required Instrument instrument,
    required Decimal price,

    /// Percent change over the last 24 hours, e.g. `-1.939`. Null when the
    /// source does not provide it.
    required Decimal? change24hPct,
    required DateTime at,
  }) = _Quote;
}
