import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// A candle from four numbers; the volume does not matter here.
Candle c(int i, String open, String high, String low, String close) => Candle(
  openTime: DateTime.utc(2026, 9).add(Duration(hours: i)),
  open: Decimal.parse(open),
  high: Decimal.parse(high),
  low: Decimal.parse(low),
  close: Decimal.parse(close),
  volume: Decimal.one,
);

Decimal d(String s) => Decimal.parse(s);
