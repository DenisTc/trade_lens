/// TradeLens · backtests of a grid and a DCA bot over historical candles.
///
/// An estimate over historical candles, not a forecast, and the model
/// says so in its limits: no slippage, no partial fills, no price inside
/// a candle beyond the path its open, high, low and close imply, no
/// trailing, no stop-loss, spot only. Written from open descriptions of
/// both strategies; see ADR-0005 for the fill model.
library;

export 'src/dca.dart';
export 'src/grid.dart';
export 'src/metrics.dart';
export 'src/money.dart';
export 'src/path.dart';
export 'src/result.dart';
