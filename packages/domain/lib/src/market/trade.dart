import 'package:core/core.dart';
import 'package:domain/src/market/instrument.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'trade.freezed.dart';

/// One executed trade from the public trade stream.
@freezed
abstract class Trade with _$Trade {
  const factory Trade({
    required Instrument instrument,
    required String id,
    required Decimal price,
    required Decimal qty,
    required DateTime at,

    /// True when the buyer was the maker, i.e. the trade was a sell.
    required bool isBuyerMaker,
  }) = _Trade;
}
