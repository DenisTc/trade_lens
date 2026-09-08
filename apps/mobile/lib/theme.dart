import 'package:flutter/material.dart';

/// Design tokens in one place. Neutral palette on purpose: the brand must not
/// resemble any exchange (see spec, "Условия источников").
abstract final class TradeLensTheme {
  static const seed = Color(0xFF3A56C7);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(colorScheme: scheme, useMaterial3: true);
  }
}
