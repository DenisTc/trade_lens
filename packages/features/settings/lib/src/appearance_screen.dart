import 'dart:async';

import 'package:features_settings/src/settings_screen.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Match system, dark or light, each with a thumbnail of the palette.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current =
        ref.watch(appThemeSettingProvider).value ?? ThemeMode.system;
    final t = context.tokens;
    final options = [
      (
        ThemeMode.system,
        l10n.themeSystemHint,
        [TradeLensPalette.dark, TradeLensPalette.light],
      ),
      (ThemeMode.dark, l10n.themeDarkHint, [TradeLensPalette.dark]),
      (ThemeMode.light, l10n.themeLightHint, [TradeLensPalette.light]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearance)),
      body: ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        children: [
          Divider(color: t.line),
          for (final (mode, hint, palettes) in options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: mode == current,
              child: SettingsRow(
                key: Key('theme_${mode.name}'),
                title: themeModeLabel(l10n, mode),
                subtitle: hint,
                onTap: () => unawaited(
                  ref.read(appThemeSettingProvider.notifier).choose(mode),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in palettes)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ExcludeSemantics(
                          child: ThemeThumbnail(
                            palette: p,
                            width: palettes.length == 1 ? 96 : 46,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    _Check(selected: mode == current),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : Colors.transparent,
        border: selected ? null : Border.all(color: t.line, width: 1.5),
      ),
      child: selected ? Icon(Icons.check, size: 16, color: t.onAccent) : null,
    );
  }
}

/// A 64 px tall screen-in-miniature: ring and wordmark bar, three rows with
/// a signed bar on the right.
class ThemeThumbnail extends StatelessWidget {
  const ThemeThumbnail({required this.palette, super.key, this.width = 96});

  final TradeLensTokens palette;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    // Widths are fractions of the inner width so the 46 px variant fits.
    Widget bar(int flex, Color c) => Flexible(
      flex: flex,
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
    Widget row(Color c) => SizedBox(
      height: 12,
      child: Row(
        children: [
          bar(22, p.text.withValues(alpha: 0.8)),
          const Spacer(flex: 36),
          bar(18, c),
        ],
      ),
    );
    return Container(
      width: width,
      height: 64,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 10,
            child: Row(
              children: [
                LensRing(size: 9, color: p.accent, dot: false, gap: false),
                const SizedBox(width: 4),
                bar(26, p.text),
                const Spacer(flex: 50),
              ],
            ),
          ),
          const SizedBox(height: 3),
          row(p.up),
          row(p.down),
          row(p.up),
        ],
      ),
    );
  }
}
