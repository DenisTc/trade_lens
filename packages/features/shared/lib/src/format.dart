import 'package:core/core.dart';
import 'package:intl/intl.dart';

/// Locale-aware display formatting (spec: "Числа и даты через intl по
/// локали"). Values are `Decimal` until this point; the `double` handed to
/// `NumberFormat` is a rendering step, never arithmetic.
abstract final class MoneyFormat {
  /// Fraction digits follow the magnitude so BTC shows `78,339.52` and a
  /// sub-cent token shows `0.000123`.
  static int digitsFor(Decimal value) {
    final abs = value.abs();
    return abs >= Decimal.fromInt(1000)
        ? 2
        : abs >= Decimal.one
        ? 4
        : 6;
  }

  static String price(Decimal value, {String? locale, int? digits}) {
    final d = digits ?? digitsFor(value);
    return NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: d,
    ).format(value.toDouble());
  }

  /// `+1.94%` / `-0.30%`; null when the source has no 24h figure.
  static String? changePct(Decimal? pct, {String? locale}) {
    if (pct == null) return null;
    final number = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 2,
    ).format(pct.abs().toDouble());
    final sign = pct.sign < 0 ? '-' : '+';
    return '$sign$number%';
  }

  static String quantity(Decimal value, {String? locale}) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 4,
      ).format(value.toDouble());

  static String time(DateTime at, {String? locale}) =>
      DateFormat.Hm(locale).format(at.toLocal());

  static String date(DateTime at, {String? locale}) =>
      DateFormat.yMd(locale).format(at.toLocal());
}
