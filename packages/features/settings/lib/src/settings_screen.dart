import 'package:features_settings/src/source_choice.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hub: one row per topic, each opening its own screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    required this.onOpenDataSource,
    required this.onOpenLanguage,
    required this.onOpenAbout,
    super.key,
  });

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        children: [
          ListTile(
            key: const Key('settings_source'),
            leading: const Icon(Icons.travel_explore_outlined),
            title: Text(l10n.settingsSource),
            subtitle: Text(
              choice == SourceChoice.auto
                  ? '${l10n.settingsSourceAuto} · ${source?.attribution ?? '…'}'
                  : source?.attribution ?? '…',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenDataSource,
          ),
          ListTile(
            key: const Key('settings_language'),
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(
              locale == null ? l10n.languageSystem : languageName(locale),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenLanguage,
          ),
          ListTile(
            key: const Key('settings_about'),
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.about),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenAbout,
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
