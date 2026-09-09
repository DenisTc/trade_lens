import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The one brand mark: a lens ring with an aperture gap and a centre dot.
/// It is the app icon, the wordmark, the connection status and the
/// crosshair marker on the chart.
class LensRing extends StatelessWidget {
  const LensRing({
    required this.size,
    required this.color,
    super.key,
    this.dot = true,
    this.gap = true,
    this.strokeWidth,
  });

  final double size;
  final Color color;

  /// Centre dot; off for an "empty" ring (offline, unselected).
  final bool dot;

  /// Aperture gap at the top-right.
  final bool gap;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: LensRingPainter(
      color: color,
      dot: dot,
      gap: gap,
      strokeWidth: strokeWidth ?? math.max(1.5, size * 0.085),
    ),
  );
}

class LensRingPainter extends CustomPainter {
  const LensRingPainter({
    required this.color,
    required this.dot,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final bool dot;
  final bool gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.38;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    if (gap) {
      // 82 % of the circle, gap centred at -50° (top-right).
      const sweep = 2 * math.pi * 0.82;
      const start = -50 * math.pi / 180 + (2 * math.pi - sweep) / 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        stroke,
      );
    } else {
      canvas.drawCircle(c, r, stroke);
    }
    if (dot) {
      canvas.drawCircle(c, size.shortestSide * 0.13, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(LensRingPainter old) =>
      old.color != color ||
      old.dot != dot ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}
