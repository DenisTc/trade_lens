import 'package:flutter/foundation.dart';

/// A trade drawn on the chart: a triangle at a price on the candle that
/// opened at [at], pointing up for a buy and down for a sell.
@immutable
final class ChartMarker {
  const ChartMarker({required this.at, required this.price, required this.up});

  final DateTime at;
  final double price;
  final bool up;

  @override
  bool operator ==(Object other) =>
      other is ChartMarker &&
      other.at == at &&
      other.price == price &&
      other.up == up;

  @override
  int get hashCode => Object.hash(at, price, up);
}
