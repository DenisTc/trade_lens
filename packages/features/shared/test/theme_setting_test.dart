import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('themeModeFromStorage: unknown and null mean system', () {
    expect(themeModeFromStorage(null), ThemeMode.system);
    expect(themeModeFromStorage('dark'), ThemeMode.dark);
    expect(themeModeFromStorage('light'), ThemeMode.light);
    expect(themeModeFromStorage('neon'), ThemeMode.system);
  });

  test('AppThemeSetting reads, writes and clears ui.theme', () async {
    final settings = FakeSettingsStore()..values[SettingsKeys.uiTheme] = 'dark';
    final container = ProviderContainer(
      retry: noRetry,
      overrides: fakeOverrides(
        source: FakeMarketDataSource(),
        settings: settings,
      ),
    );
    addTearDown(container.dispose);
    final sub = container.listen(appThemeSettingProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(appThemeSettingProvider.future);
    expect(container.read(appThemeSettingProvider).value, ThemeMode.dark);

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await container
        .read(appThemeSettingProvider.notifier)
        .choose(ThemeMode.light);
    await settle();
    expect(settings.values[SettingsKeys.uiTheme], 'light');
    expect(container.read(appThemeSettingProvider).value, ThemeMode.light);

    await container
        .read(appThemeSettingProvider.notifier)
        .choose(ThemeMode.system);
    await settle();
    expect(settings.values.containsKey(SettingsKeys.uiTheme), isFalse);
    expect(container.read(appThemeSettingProvider).value, ThemeMode.system);
  });

  testWidgets('buildTradeLensTheme carries tokens, fonts and a flat app bar', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = buildTradeLensTheme(brightness);
      final tokens = theme.extension<TradeLensTokens>()!;
      expect(tokens, TradeLensTokens.of(brightness));
      expect(theme.scaffoldBackgroundColor, tokens.bg);
      expect(theme.colorScheme.primary, tokens.accent);
      expect(theme.textTheme.bodyMedium?.fontFamily, TradeLensFonts.sans);
      expect(theme.textTheme.displaySmall?.fontFamily, TradeLensFonts.mono);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
    }
  });

  test('signed colours and chip tints follow the sign', () {
    const t = TradeLensPalette.dark;
    expect(t.signed(1), t.up);
    expect(t.signed(-1), t.down);
    expect(t.signed(0), t.muted);
    expect(t.signed(null), t.muted);
    expect(t.signedBg(1), t.upBg);
    expect(t.signedBg(-1), t.downBg);
    expect(t.signedBg(null), t.raised);
  });
}
