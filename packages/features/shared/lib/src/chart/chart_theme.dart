import 'package:chart/chart.dart';
import 'package:features_shared/src/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The chart in the app's colours. Every screen that draws candles —
/// the pair, the backtest — draws them the same way.
CandleChartTheme tradeLensChartTheme(BuildContext context) {
  final t = context.tokens;
  return CandleChartTheme(
    up: t.up,
    down: t.down,
    grid: t.line,
    axisText: t.muted,
    crosshair: t.accent,
    crosshairLabelBackground: t.accent,
    crosshairLabelText: t.onAccent,
    fontFamily: TradeLensFonts.mono,
  );
}
