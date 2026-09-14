import 'package:core/core.dart';
import 'package:domain/domain.dart';

/// The one thing a candle says about the price inside it: where it
/// started, how far it went each way, where it ended. The order of the
/// extremes is not recorded, so the model assumes the common shape — a
/// rising candle visits its low first, a falling one its high first —
/// and walks four points: open, first extreme, second extreme, close.
///
/// A resting order fills when the walk crosses its price. Between two
/// points the walk is monotonic, so the orders it crosses fill in price
/// order, and an order placed by a fill can itself fill later in the
/// same walk. That is the whole fill model; ADR-0005 states its limits.
List<Decimal> candlePath(Candle c) => c.close >= c.open
    ? [c.open, c.low, c.high, c.close]
    : [c.open, c.high, c.low, c.close];
