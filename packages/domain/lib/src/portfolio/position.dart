import 'package:core/core.dart';
import 'package:domain/src/market/asset.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'position.freezed.dart';

/// A manually entered holding: quantity of an asset bought at an average
/// price in a quote currency. Money is `Decimal`; the storage layer keeps
/// it as text.
@freezed
abstract class Position with _$Position {
  const factory Position({
    required String id,
    required Asset asset,

    /// Quote currency of [avgPrice], e.g. `USDT`. Valuation only uses
    /// quotes in the same currency.
    required String quote,
    required Decimal qty,
    required Decimal avgPrice,
    required DateTime createdAt,

    /// Free text added in schema v2.
    String? note,
  }) = _Position;

  const Position._();

  Decimal get cost => qty * avgPrice;
}
