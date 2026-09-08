import 'package:chart/chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paints a line for two or more values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 100,
          height: 30,
          child: Sparkline(values: [1, 3, 2, 5, 4]),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('does not crash on empty or flat input', (tester) async {
    for (final values in [
      <double>[],
      <double>[1],
      <double>[2, 2, 2],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 100,
            height: 30,
            child: Sparkline(values: values),
          ),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('shouldRepaint compares values by identity, not content', () {
    final a = [1.0, 2.0];
    const color = Colors.blue;
    final painter = SparklinePainter(values: a, color: color);
    expect(
      painter.shouldRepaint(SparklinePainter(values: a, color: color)),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const SparklinePainter(values: [1.0, 2.0], color: color),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(SparklinePainter(values: a, color: Colors.red)),
      isTrue,
    );
  });
}
