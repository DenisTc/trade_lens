import 'package:core/core.dart';
import 'package:rational/rational.dart';

/// Scales the engine keeps its numbers at, so a run over thousands of
/// candles does not grow digits without bound: prices to twelve places,
/// quantities to eight. Division alone only caps non-terminating results.
///
/// Directions matter: a quantity rounds down, so what it costs never
/// exceeds what was there to spend; a take-profit rounds up, so the
/// sale nets at least what was asked.
abstract final class Money {
  static const priceScale = 12;
  static const qtyScale = 8;

  static Decimal price(Rational r) => r
      .toDecimal(scaleOnInfinitePrecision: priceScale)
      .round(scale: priceScale);

  static Decimal priceUp(Rational r) => r
      .toDecimal(scaleOnInfinitePrecision: priceScale + 1)
      .ceil(scale: priceScale);

  static Decimal qty(Rational r) => r
      .toDecimal(scaleOnInfinitePrecision: qtyScale + 1)
      .floor(scale: qtyScale);

  static Decimal roundPrice(Decimal d) => d.round(scale: priceScale);
}
