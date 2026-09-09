import 'package:flutter/material.dart';

/// Design tokens of the «Оптика» direction (`docs/design/brief.md`). Two
/// palettes, dark first; one warm accent; rise and fall at the same
/// lightness so neither shouts. The palette must not echo any exchange's
/// brand.
abstract final class TradeLensPalette {
  static const dark = TradeLensTokens(
    bg: Color(0xFF0C1117),
    surface: Color(0xFF121922),
    raised: Color(0xFF1A2330),
    line: Color(0xFF243040),
    text: Color(0xFFE8EEF4),
    muted: Color(0xFF8A9AAB),
    accent: Color(0xFFF2B94A),
    accentInk: Color(0xFFF2B94A),
    onAccent: Color(0xFF14110A),
    up: Color(0xFF3DDC97),
    down: Color(0xFFFF6B5E),
    warn: Color(0xFFE0AE4A),
    glass: Color(0x8C121922),
    glassLine: Color(0x1FFFFFFF),
    shadow: Color(0x73000000),
  );

  static const light = TradeLensTokens(
    bg: Color(0xFFF2F5FA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFE5EBF5),
    line: Color(0xFFD3DCEA),
    text: Color(0xFF0F172A),
    muted: Color(0xFF5B6B82),
    accent: Color(0xFFC7880E),
    accentInk: Color(0xFF8F5E05),
    onAccent: Color(0xFF14110A),
    up: Color(0xFF0F7F50),
    down: Color(0xFFC23636),
    warn: Color(0xFFA8701B),
    glass: Color(0x9EFFFFFF),
    glassLine: Color(0x1A0F172A),
    shadow: Color(0x240F172A),
  );
}

/// Font families bundled in this package (`assets/fonts`, OFL). Text is
/// Onest, every number is IBM Plex Mono with tabular figures.
abstract final class TradeLensFonts {
  static const sans = 'packages/features_shared/Onest';
  static const mono = 'packages/features_shared/IBMPlexMono';
}

/// Semantic colours features read through `context.tokens`.
@immutable
class TradeLensTokens extends ThemeExtension<TradeLensTokens> {
  const TradeLensTokens({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.up,
    required this.down,
    required this.warn,
    required this.glass,
    required this.glassLine,
    required this.shadow,
  });

  factory TradeLensTokens.of(Brightness brightness) =>
      brightness == Brightness.dark
      ? TradeLensPalette.dark
      : TradeLensPalette.light;

  /// Screen background.
  final Color bg;

  /// Cards, sheets, the tab bar body.
  final Color surface;

  /// Icon squares, skeletons, pressed rows.
  final Color raised;

  /// Hairlines and dividers.
  final Color line;
  final Color text;
  final Color muted;

  /// The one accent: lens ring, crosshair, primary button, active tab.
  final Color accent;

  /// Accent for text-sized uses (labels, links): darker in the light theme
  /// so 12 px text keeps 4.5:1 on the background. Same as [accent] in dark.
  final Color accentInk;
  final Color onAccent;
  final Color up;
  final Color down;
  final Color warn;

  /// Translucent fill of the floating tab bar (over a backdrop blur).
  final Color glass;
  final Color glassLine;
  final Color shadow;

  /// 12 % tint behind a signed chip.
  Color get upBg => up.withValues(alpha: 0.12);
  Color get downBg => down.withValues(alpha: 0.12);
  Color get accentBg => accent.withValues(alpha: 0.14);

  /// Colour for a signed change: up, down, or muted for zero/unknown.
  Color signed(num? sign) => sign == null
      ? muted
      : sign > 0
      ? up
      : sign < 0
      ? down
      : muted;

  /// Chip tint for a signed change.
  Color signedBg(num? sign) => sign == null
      ? raised
      : sign > 0
      ? upBg
      : sign < 0
      ? downBg
      : raised;

  @override
  TradeLensTokens copyWith({
    Color? bg,
    Color? surface,
    Color? raised,
    Color? line,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentInk,
    Color? onAccent,
    Color? up,
    Color? down,
    Color? warn,
    Color? glass,
    Color? glassLine,
    Color? shadow,
  }) => TradeLensTokens(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    line: line ?? this.line,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    accentInk: accentInk ?? this.accentInk,
    onAccent: onAccent ?? this.onAccent,
    up: up ?? this.up,
    down: down ?? this.down,
    warn: warn ?? this.warn,
    glass: glass ?? this.glass,
    glassLine: glassLine ?? this.glassLine,
    shadow: shadow ?? this.shadow,
  );

  @override
  TradeLensTokens lerp(TradeLensTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TradeLensTokens(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      accent: l(accent, other.accent),
      accentInk: l(accentInk, other.accentInk),
      onAccent: l(onAccent, other.onAccent),
      up: l(up, other.up),
      down: l(down, other.down),
      warn: l(warn, other.warn),
      glass: l(glass, other.glass),
      glassLine: l(glassLine, other.glassLine),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Type ramp. Sizes follow the canvas: screen title 24, big price 34,
/// ticker 16, row price 15, body 14, caption 12, chart axis 10.
abstract final class TradeLensText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
  }) => TextStyle(
    fontFamily: TradeLensFonts.mono,
    fontSize: size,
    fontWeight: weight,
    fontFeatures: _tabular,
    color: color,
    height: height,
  );

  static TextTheme textTheme(TradeLensTokens t) {
    TextStyle sans(
      double size,
      FontWeight weight, {
      Color? color,
      double? ls,
    }) => TextStyle(
      fontFamily: TradeLensFonts.sans,
      fontSize: size,
      fontWeight: weight,
      color: color ?? t.text,
      letterSpacing: ls,
      height: 1.25,
    );
    return TextTheme(
      // Big price.
      displaySmall: mono(size: 34, weight: FontWeight.w600, color: t.text),
      headlineMedium: mono(size: 28, weight: FontWeight.w600, color: t.text),
      // Screen title / pair title / app-bar title.
      headlineSmall: sans(24, FontWeight.w600, ls: -0.5),
      titleLarge: sans(20, FontWeight.w600, ls: -0.4),
      // Ticker, row title.
      titleMedium: sans(16, FontWeight.w600),
      titleSmall: sans(14, FontWeight.w600),
      bodyLarge: sans(16, FontWeight.w400),
      bodyMedium: sans(14, FontWeight.w400),
      bodySmall: sans(12, FontWeight.w400, color: t.muted),
      labelLarge: sans(14, FontWeight.w500),
      labelMedium: sans(12, FontWeight.w500, color: t.muted, ls: 0.2),
      labelSmall: sans(11, FontWeight.w500, color: t.muted, ls: 0.2),
    );
  }
}

/// Material theme built from the tokens. `ThemeMode` picks light or dark;
/// nothing else in the app knows about brightness.
ThemeData buildTradeLensTheme(Brightness brightness) {
  final t = TradeLensTokens.of(brightness);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentBg,
    onPrimaryContainer: t.accentInk,
    secondary: t.up,
    onSecondary: t.onAccent,
    error: t.down,
    onError: t.onAccent,
    errorContainer: t.downBg,
    onErrorContainer: t.down,
    surface: t.bg,
    onSurface: t.text,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.raised,
    surfaceContainerHighest: t.raised,
    outline: t.line,
    outlineVariant: t.line,
    inverseSurface: t.text,
    onInverseSurface: t.bg,
    shadow: t.shadow,
  );
  final text = TradeLensText.textTheme(t);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: text,
    fontFamily: TradeLensFonts.sans,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: t.text, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      toolbarHeight: 56,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: t.text, size: 24),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: text.bodySmall,
      iconColor: t.accent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minVerticalPadding: 12,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accentInk,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        side: BorderSide(color: t.line),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      hintStyle: text.bodyMedium?.copyWith(color: t.muted),
      labelStyle: text.bodyMedium?.copyWith(color: t.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.line,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.raised,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: text.bodySmall?.copyWith(color: t.text),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    extensions: [t],
  );
}

extension TradeLensTokensX on BuildContext {
  TradeLensTokens get tokens =>
      Theme.of(this).extension<TradeLensTokens>() ??
      TradeLensTokens.of(Theme.of(this).brightness);
}
