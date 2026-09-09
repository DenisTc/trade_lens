import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Formats axis and crosshair labels.
abstract final class ChartFormat {
  /// Fraction digits chosen from the visible price range so labels stay
  /// distinct without drowning in digits.
  static int priceDigits(double range) {
    if (range <= 0) return 2;
    final magnitude = math.log(range) / math.ln10;
    return (2 - magnitude.floor()).clamp(0, 8);
  }

  static String price(double value, int digits) =>
      value.toStringAsFixed(digits);

  /// [local] false keeps UTC, which golden tests use so the images do not
  /// depend on the machine's time zone.
  static String time(DateTime t, Duration interval, {bool local = true}) {
    final local_ = local ? t.toLocal() : t.toUtc();
    return _time(local_, interval);
  }

  /// Full stamp for the crosshair: the day is always shown, the time
  /// unless the interval is daily or longer.
  static String timeFull(DateTime t, Duration interval, {bool local = true}) {
    final l = local ? t.toLocal() : t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${two(l.day)}.${two(l.month)}';
    if (interval >= const Duration(days: 1)) return day;
    return '$day ${two(l.hour)}:${two(l.minute)}';
  }

  static String _time(DateTime local, Duration interval) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (interval >= const Duration(days: 1)) {
      return '${two(local.day)}.${two(local.month)}';
    }
    if (local.hour == 0 && local.minute == 0) {
      return '${two(local.day)}.${two(local.month)}';
    }
    return '${two(local.hour)}:${two(local.minute)}';
  }

  /// "Nice" step for [count] price ticks across [range].
  static double niceStep(double range, int count) {
    final raw = range / count;
    if (raw <= 0) return 1;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    final normalized = raw / magnitude;
    final nice = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 5
        ? 5
        : 10;
    return (nice * magnitude).toDouble();
  }
}

/// Caches laid-out labels by text so repaints do not re-shape text.
final class LabelCache {
  LabelCache({required this.style, this.capacity = 256});

  final TextStyle style;
  final int capacity;
  final Map<String, TextPainter> _cache = {};

  TextPainter layout(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    if (_cache.length >= capacity) _cache.remove(_cache.keys.first)?.dispose();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return _cache[text] = painter;
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
}
