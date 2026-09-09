import 'package:flutter/material.dart';

/// Design tokens in one file (spec, "Тёмная тема: дизайн-токены одним
/// файлом"). The palette is deliberately neutral: the app must not echo
/// any exchange's brand.
abstract final class TradeLensPalette {
  static const seed = Color(0xFF3A56C7);
  static const upLight = Color(0xFF1E8E5A);
  static const downLight = Color(0xFFC63A2F);
  static const upDark = Color(0xFF5ACB8E);
  static const downDark = Color(0xFFE5715F);
  static const warnLight = Color(0xFFA8701B);
  static const warnDark = Color(0xFFE0AE4A);
}

/// Semantic colours features read through `context.tokens`.
@immutable
class TradeLensTokens extends ThemeExtension<TradeLensTokens> {
  const TradeLensTokens({
    required this.up,
    required this.down,
    required this.warn,
    required this.muted,
  });

  factory TradeLensTokens.of(Brightness brightness, ColorScheme scheme) =>
      brightness == Brightness.dark
      ? TradeLensTokens(
          up: TradeLensPalette.upDark,
          down: TradeLensPalette.downDark,
          warn: TradeLensPalette.warnDark,
          muted: scheme.onSurfaceVariant,
        )
      : TradeLensTokens(
          up: TradeLensPalette.upLight,
          down: TradeLensPalette.downLight,
          warn: TradeLensPalette.warnLight,
          muted: scheme.onSurfaceVariant,
        );

  final Color up;
  final Color down;
  final Color warn;
  final Color muted;

  /// Colour for a signed change: up, down, or muted for zero/unknown.
  Color signed(num? sign) => sign == null
      ? muted
      : sign > 0
      ? up
      : sign < 0
      ? down
      : muted;

  @override
  TradeLensTokens copyWith({
    Color? up,
    Color? down,
    Color? warn,
    Color? muted,
  }) => TradeLensTokens(
    up: up ?? this.up,
    down: down ?? this.down,
    warn: warn ?? this.warn,
    muted: muted ?? this.muted,
  );

  @override
  TradeLensTokens lerp(TradeLensTokens? other, double t) {
    if (other == null) return this;
    return TradeLensTokens(
      up: Color.lerp(up, other.up, t)!,
      down: Color.lerp(down, other.down, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

/// Material 3 theme with the tokens attached. `ThemeMode.system` picks
/// light or dark; nothing else in the app knows about brightness.
ThemeData buildTradeLensTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: TradeLensPalette.seed,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [TradeLensTokens.of(brightness, scheme)],
  );
}

extension TradeLensTokensX on BuildContext {
  TradeLensTokens get tokens =>
      Theme.of(this).extension<TradeLensTokens>() ??
      TradeLensTokens.of(Theme.of(this).brightness, Theme.of(this).colorScheme);
}
