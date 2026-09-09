import 'package:features_settings/src/source_choice.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hub: one row per topic, each opening its own screen. The version lives
/// on the About screen only.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    required this.onOpenDataSource,
    required this.onOpenLanguage,
    required this.onOpenAbout,
    super.key,
    this.onOpenAppearance,
    this.onOpenAi,
  });

  final VoidCallback? onOpenAppearance;
  final VoidCallback? onOpenAi;
  final VoidCallback onOpenDataSource;
  final VoidCallback onOpenLanguage;
  final VoidCallback onOpenAbout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final choice =
        ref.watch(sourceChoiceSettingProvider).value ?? SourceChoice.auto;
    final source = ref.watch(marketDataSourceProvider).value;
    final locale = ref.watch(appLocaleSettingProvider).value;
    final mode = ref.watch(appThemeSettingProvider).value ?? ThemeMode.system;
    final t = context.tokens;
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(title: l10n.tabSettings),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(
                top: 8,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
              children: [
                Divider(color: t.line),
                if (onOpenAppearance != null)
                  SettingsRow(
                    key: const Key('settings_appearance'),
                    icon: Icons.contrast,
                    title: l10n.appearance,
                    subtitle: themeModeLabel(l10n, mode),
                    onTap: onOpenAppearance,
                  ),
                SettingsRow(
                  key: const Key('settings_source'),
                  icon: Icons.public,
                  title: l10n.settingsSource,
                  subtitle: choice == SourceChoice.auto
                      ? '${l10n.settingsSourceAuto} · ${source?.attribution ?? '…'}'
                      : source?.attribution ?? '…',
                  onTap: onOpenDataSource,
                ),
                if (onOpenAi != null)
                  SettingsRow(
                    key: const Key('settings_ai'),
                    icon: Icons.auto_awesome_outlined,
                    title: l10n.aiSettingsRow,
                    subtitle: switch (ref.watch(aiReadinessProvider)) {
                      AiReadiness.ready => l10n.aiSettingsRowReady,
                      AiReadiness.noConsent => l10n.aiSettingsRowNoConsent,
                      AiReadiness.disabled ||
                      AiReadiness.noKey => l10n.aiSettingsRowNoKey,
                    },
                    onTap: onOpenAi,
                  ),
                SettingsRow(
                  key: const Key('settings_language'),
                  icon: Icons.translate,
                  title: l10n.language,
                  subtitle: locale == null
                      ? l10n.languageSystem
                      : languageName(locale),
                  onTap: onOpenLanguage,
                ),
                SettingsRow(
                  key: const Key('settings_about'),
                  icon: Icons.info_outline,
                  title: l10n.about,
                  onTap: onOpenAbout,
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.settingsNote,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Endonym of a supported language.
String languageName(Locale locale) => switch (locale.languageCode) {
  'ru' => 'Русский',
  _ => 'English',
};

String themeModeLabel(SharedLocalizations l10n, ThemeMode mode) =>
    switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.dark => l10n.themeDark,
      ThemeMode.light => l10n.themeLight,
    };
