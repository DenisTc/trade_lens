import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tiny line chart of recent values, e.g. the last 60 ticks of a pair.
///
/// Input is `double` on purpose: this is the presentation boundary. Money
/// stays `Decimal` in the domain; the conversion happens in the caller's
/// view model, once.
class Sparkline extends StatelessWidget {
  const Sparkline({
    required this.values,
    super.key,
    this.color,
    this.strokeWidth = 1.5,
    this.fill = true,
  });

  final List<double> values;
  final Color? color;
  final double strokeWidth;

  /// Soft gradient under the line.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(
      painter: SparklinePainter(
        values: values,
        color: lineColor,
        strokeWidth: strokeWidth,
        fill: fill,
      ),
      size: Size.infinite,
    );
  }
}

class SparklinePainter extends CustomPainter {
  const SparklinePainter({
    required this.values,
    required this.color,
    this.strokeWidth = 1.5,
    this.fill = true,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      min = math.min(min, v);
      max = math.max(max, v);
    }
    final range = max - min;
    final inset = strokeWidth;
    final stepX = (size.width - inset * 2) / (values.length - 1);
    double y(double v) => range == 0
        ? size.height / 2
        : inset + (size.height - inset * 2) * (1 - (v - min) / range);

    final path = Path()..moveTo(inset, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(inset + stepX * i, y(values[i]));
    }

    if (fill) {
      final area = Path.from(path)
        ..lineTo(inset + stepX * (values.length - 1), size.height)
        ..lineTo(inset, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      !identical(oldDelegate.values, values) ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.fill != fill;
}
