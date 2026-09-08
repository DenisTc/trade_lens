import 'package:core/core.dart';

/// Display formatting for prices and percentages. Locale-aware formatting
/// with `intl` arrives with localization (day 5); the rules here are the
/// ones that do not depend on locale.
///
/// Fraction digits follow the magnitude so BTC shows `78 339.52` and a
/// sub-cent token shows `0.000123`.
String formatPrice(Decimal price) {
  final abs = price.abs();
  final digits = abs >= Decimal.fromInt(1000)
      ? 2
      : abs >= Decimal.one
      ? 4
      : 6;
  return _groupThousands(price.toStringAsFixed(digits));
}

/// `+1.94%` / `-0.30%`; null when the source has no 24h figure.
String? formatChangePct(Decimal? pct) {
  if (pct == null) return null;
  final sign = pct.sign >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(2)}%';
}

String _groupThousands(String fixed) {
  final negative = fixed.startsWith('-');
  final body = negative ? fixed.substring(1) : fixed;
  final dot = body.indexOf('.');
  final intPart = dot == -1 ? body : body.substring(0, dot);
  final fracPart = dot == -1 ? '' : body.substring(dot);
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer$fracPart';
}
