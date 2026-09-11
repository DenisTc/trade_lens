/// TradeLens · chart widgets on `CustomPainter`, no feature dependencies
/// (future pub.dev package).
///
/// `CandleChart` draws candles, volume and both axes on one painter and the
/// crosshair on a second one, so pointer movement never repaints candles.
/// Money is `double` here: this is the presentation boundary.
library;

export 'src/axes.dart' show ChartFormat;
export 'src/candle_chart.dart';
export 'src/chart_theme.dart';
export 'src/crosshair_painter.dart' show CrosshairInfo;
export 'src/indicators.dart';
export 'src/model.dart';
export 'src/series.dart';
export 'src/sparkline.dart';
export 'src/viewport.dart';
