import 'dart:math';

/// Exponential backoff 1, 2, 4, 8 … capped at [max], with ±[jitter]
/// so a fleet of clients does not reconnect in lockstep after an outage.
final class Backoff {
  Backoff({
    this.base = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration base;
  final Duration max;

  /// Fraction of the delay used as the jitter range, e.g. 0.2 → ±20 %.
  final double jitter;
  final Random _random;

  int _attempt = 0;

  int get attempt => _attempt;

  Duration next() {
    final exponent = _attempt.clamp(0, 30);
    final raw = base * (1 << exponent);
    final capped = raw > max ? max : raw;
    _attempt++;
    final spread = (_random.nextDouble() * 2 - 1) * jitter;
    return Duration(
      microseconds: (capped.inMicroseconds * (1 + spread)).round(),
    );
  }

  void reset() => _attempt = 0;
}
