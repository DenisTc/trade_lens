import 'package:flutter/material.dart';

/// Colours and sizes of the candle chart. Built from the app theme by
/// default so light and dark modes need no extra wiring.
@immutable
final class CandleChartTheme {
  const CandleChartTheme({
    required this.up,
    required this.down,
    required this.grid,
    required this.axisText,
    required this.crosshair,
    required this.crosshairLabelBackground,
    required this.crosshairLabelText,
    this.fontFamily,
    this.axisTextSize = 10,
    this.priceAxisWidth = 56,
    this.timeAxisHeight = 18,
    this.volumeFraction = 0.2,
    this.crosshairRingRadius = 6,
  });

  factory CandleChartTheme.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CandleChartTheme(
      up: const Color(0xFF1E8E5A),
      down: const Color(0xFFC63A2F),
      grid: scheme.outlineVariant.withValues(alpha: 0.5),
      axisText: scheme.onSurfaceVariant,
      crosshair: scheme.onSurface.withValues(alpha: 0.6),
      crosshairLabelBackground: scheme.inverseSurface,
      crosshairLabelText: scheme.onInverseSurface,
      fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
    );
  }

  final Color up;
  final Color down;
  final Color grid;
  final Color axisText;
  final Color crosshair;
  final Color crosshairLabelBackground;
  final Color crosshairLabelText;

  /// Font of axis and crosshair labels; null means the platform default.
  final String? fontFamily;
  final double axisTextSize;
  final double priceAxisWidth;
  final double timeAxisHeight;

  /// Share of the plot height given to volume bars (0 hides them).
  final double volumeFraction;

  /// Radius of the ring drawn where the crosshair lines meet.
  final double crosshairRingRadius;

  @override
  bool operator ==(Object other) =>
      other is CandleChartTheme &&
      other.up == up &&
      other.down == down &&
      other.grid == grid &&
      other.axisText == axisText &&
      other.crosshair == crosshair &&
      other.crosshairLabelBackground == crosshairLabelBackground &&
      other.crosshairLabelText == crosshairLabelText &&
      other.fontFamily == fontFamily &&
      other.axisTextSize == axisTextSize &&
      other.priceAxisWidth == priceAxisWidth &&
      other.timeAxisHeight == timeAxisHeight &&
      other.volumeFraction == volumeFraction &&
      other.crosshairRingRadius == crosshairRingRadius;

  @override
  int get hashCode => Object.hash(
    up,
    down,
    grid,
    axisText,
    crosshair,
    crosshairLabelBackground,
    crosshairLabelText,
    fontFamily,
    axisTextSize,
    priceAxisWidth,
    timeAxisHeight,
    volumeFraction,
    crosshairRingRadius,
  );
}
